import { test } from 'node:test';
import assert from 'node:assert/strict';
import { _scanStateCities as scanStateCities, _newStateRecord as newStateRecord } from './stateCityOrchestrator.js';

const oneStarBusiness = (name, access = { complete: true, status: 'ok', sorted: true }) => ({
  name,
  category: 'Car Wash',
  address: '1 Main St',
  phone: '(415) 555-0100',
  website: 'https://x.example',
  mapsUrl: `https://www.google.com/maps/place/${encodeURIComponent(name)}`,
  rating: 4,
  totalReviews: 50,
  reviews: [{ stars: 1, reviewer: 'Sam', date: '2 days ago', text: 'bad', link: null }],
  reviewAccess: access,
  source: 'google_maps',
});

function makeJob(scrapeLocationFn, extra = {}) {
  return {
    concurrency: 2,
    dateRange: '28',
    maxResultsPerCity: 10,
    analyze: false,
    browser: null,
    cancelled: false,
    paused: false,
    requireSignIn: true,
    stoppedReason: null,
    scrapeLocationFn,
    collectedLeadsByState: { 'Car Wash': {} },
    activityLog: [],
    ...extra,
  };
}

test('every city read completely: the state is done and nothing is flagged', async () => {
  const job = makeJob(async (_c, location) => [oneStarBusiness(`Wash ${location}`)]);
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Houston']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(rec.status, 'done');
  assert.deepEqual(rec.covered.sort(), ['Austin', 'Dallas', 'Houston']);
  assert.equal(rec.failed.length, 0);
  assert.equal(rec.incompleteBusinesses, 0);
  assert.equal(rec.leadsCollected, 3);
});

test('a city that fails once is retried, and then counts as covered', async () => {
  const calls = {};
  const job = makeJob(async (_c, location) => {
    calls[location] = (calls[location] || 0) + 1;
    if (location.includes('Dallas') && calls[location] === 1) throw new Error('page crashed');
    return [oneStarBusiness(`Wash ${location}`)];
  });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(rec.status, 'done');
  assert.equal(rec.failed.length, 0);
  assert.deepEqual(rec.covered.sort(), ['Austin', 'Dallas']);
  assert.ok(Object.values(calls).some((n) => n === 2), 'Dallas was tried twice');
});

test('a city that keeps failing is recorded, and its state is NOT marked done (so Resume redoes it)', async () => {
  const job = makeJob(async (_c, location) => {
    if (location.includes('Dallas')) throw new Error('blocked');
    return [oneStarBusiness(`Wash ${location}`)];
  });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.deepEqual(rec.failed, ['Dallas']);
  assert.notEqual(rec.status, 'done');
  assert.equal(rec.status, 'cancelled', 'left resumable rather than silently complete');
});

test('businesses whose reviews could not be fully read are counted, not hidden', async () => {
  const job = makeJob(async (_c, location) => [
    oneStarBusiness(`A ${location}`),
    oneStarBusiness(`B ${location}`, { complete: false, status: 'sort_not_verified', sorted: false }),
  ]);
  const rec = newStateRecord('Texas', ['Austin']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(rec.incompleteBusinesses, 1);
  assert.equal(rec.status, 'done', 'the city was scanned; the gap is reported, not swallowed');
  assert.ok(job.activityLog.some((l) => l.level === 'warn' && /not fully read/.test(l.message)));
});

test('skipped listings are counted and warned about', async () => {
  const job = makeJob(async () => {
    const list = [oneStarBusiness('Only One')];
    Object.defineProperty(list, 'skippedListings', { value: 2, enumerable: false });
    return list;
  });
  const rec = newStateRecord('Texas', ['Austin']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(rec.skippedListings, 2);
  assert.ok(job.activityLog.some((l) => /2 listings skipped/.test(l.message)));
});

test('Google asking to sign in mid-scan stops the scan and keeps that city out of the results', async () => {
  const job = makeJob(async (_c, location) => {
    if (location.includes('Dallas')) {
      return [oneStarBusiness('Blocked', { complete: false, status: 'signin_required', sorted: false })];
    }
    return [oneStarBusiness(`Wash ${location}`)];
  }, { concurrency: 1 });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Houston']);
  await scanStateCities(job, 'Car Wash', rec);

  assert.equal(job.cancelled, true);
  assert.equal(job.stoppedReason, 'google_session_expired');
  assert.ok(rec.pending.includes('Dallas'), 'the blocked city goes back to pending so it is redone');
  assert.ok(!rec.covered.includes('Dallas'));
  assert.ok(!(job.collectedLeadsByState['Car Wash'].Texas || []).some((l) => l.business === 'Blocked'), 'its half-read results are discarded');
  assert.notEqual(rec.status, 'done');
  assert.ok(job.activityLog.some((l) => l.level === 'error' && /Sign in to Google again/.test(l.message)));
});

test('with sign-in not required (an explicit override) the same block is only counted', async () => {
  const job = makeJob(
    async () => [oneStarBusiness('Blocked', { complete: false, status: 'signin_required', sorted: false })],
    { requireSignIn: false },
  );
  const rec = newStateRecord('Texas', ['Austin']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(job.cancelled, false);
  assert.equal(rec.incompleteBusinesses, 1);
  assert.equal(rec.status, 'done');
});
