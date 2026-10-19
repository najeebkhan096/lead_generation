import { test } from 'node:test';
import assert from 'node:assert/strict';
import { _scanStateCities as scanStateCities, _newStateRecord as newStateRecord } from './stateCityOrchestrator.js';
import { GoogleBlockedError } from '../../scraper/googleBlock.js';

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
    seenPlaces: { 'Car Wash': new Set() },
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
  const texasLeads = [];
  for await (const lead of job.leadSpool.read('Car Wash', 'Texas')) texasLeads.push(lead);
  assert.ok(!texasLeads.some((l) => l.business === 'Blocked'), 'its half-read results are discarded');
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

// ---- Google's "unusual traffic" check -------------------------------------------------

test('a block pauses every worker, then the scan resumes by itself and finishes the state', async () => {
  let blockedOnce = false;
  let probes = 0;
  const job = makeJob(
    async (_c, location) => {
      if (!blockedOnce && location.includes('Dallas')) {
        blockedOnce = true;
        throw new GoogleBlockedError('/sorry/index');
      }
      return [oneStarBusiness(`Wash ${location}`)];
    },
    { concurrency: 2, blockCooldownMs: 30, probeFn: async () => (++probes < 2 ? 'blocked' : 'ok') },
  );
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Houston', 'Plano']);
  await scanStateCities(job, 'Car Wash', rec);

  assert.equal(rec.status, 'done', 'every city was covered once Google cleared');
  assert.deepEqual(rec.covered.sort(), ['Austin', 'Dallas', 'Houston', 'Plano']);
  assert.equal(rec.failed.length, 0, 'a block is not a failed city');
  assert.equal(job.blocked, null);
  assert.equal(job.paused, false);
  assert.ok(probes >= 2, 'it looked again after the first look still showed the check');
  const messages = job.activityLog.map((l) => l.message).join('\n');
  assert.match(messages, /unusual traffic/);
  assert.match(messages, /still shows its check/);
  assert.match(messages, /serving results again\. Scan resumed/);
  assert.equal(job.activityLog.filter((l) => /unusual traffic/.test(l.message) && l.level === 'error').length, 1, 'reported once, not once per worker');
});

test('a block that never clears leaves the state unfinished, never "done"', async () => {
  const job = makeJob(
    async () => {
      throw new GoogleBlockedError();
    },
    { concurrency: 2, blockCooldownMs: 20, probeFn: async () => 'blocked' },
  );
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  const running = scanStateCities(job, 'Car Wash', rec);
  await new Promise((r) => setTimeout(r, 300));
  assert.ok(job.blocked, 'still waiting for Google');
  assert.equal(rec.covered.length, 0, 'nothing was recorded as covered');
  job.cancelled = true; // the person gives up
  await running;
  assert.notEqual(rec.status, 'done');
  assert.ok(rec.pending.includes('Austin') || rec.pending.includes('Dallas'), 'the cities go back for a Resume');
  assert.equal(rec.failed.length, 0);
});

test('a city interrupted by Cancel is put back, its partial results discarded, and the state is not done', async () => {
  const job = makeJob(async (_c, location) => {
    job.cancelled = true; // Cancel is pressed while this city is being read
    return [oneStarBusiness(`Partial ${location}`)];
  }, { concurrency: 1 });
  const rec = newStateRecord('Texas', ['Austin']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(rec.covered.length, 0);
  assert.deepEqual(rec.pending, ['Austin']);
  assert.equal(rec.leadsCollected, 0);
  assert.notEqual(rec.status, 'done');
});

// ---- empty must never mean done --------------------------------------------------------------

test('a city whose search returned no result list fails (retried, then recorded): it is not "0 leads, done"', async () => {
  const job = makeJob(async (_c, location) => {
    const list = [];
    Object.defineProperty(list, 'searchStatus', { value: location.includes('Dallas') ? 'feed_missing' : 'ok' });
    if (!location.includes('Dallas')) list.push(oneStarBusiness(`Wash ${location}`));
    return list;
  });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.deepEqual(rec.failed, ['Dallas']);
  assert.notEqual(rec.status, 'done');
  assert.ok(job.activityLog.some((l) => /retry/.test(l.message)));
});

test('Google genuinely having no results for a city is fine: that city is covered', async () => {
  const job = makeJob(async () => {
    const list = [];
    Object.defineProperty(list, 'searchStatus', { value: 'no_results' });
    return list;
  });
  const rec = newStateRecord('Texas', ['Tiny Town']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(rec.status, 'done');
  assert.deepEqual(rec.covered, ['Tiny Town']);
});

test('the scan reads Google only, and hands every city the same "already read" set', async () => {
  const seen = [];
  const job = makeJob(async (_c, _l, options) => {
    seen.push({ set: options.seenPlaceIds, googleOnly: options.googleOnly });
    return [];
  });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.equal(seen.length >= 2, true);
  assert.ok(seen.every((x) => x.googleOnly === true), 'no Bing/Yelp fallback masking a failure');
  assert.ok(seen.every((x) => x.set === job.seenPlaces['Car Wash']), 'one shared set per category');
});

test('when listings start failing the scan slows itself down, and says so, before Google blocks it', async () => {
  const fed = [];
  const job = makeJob(
    async (_c, location) => {
      const list = [oneStarBusiness(`Wash ${location}`)];
      Object.defineProperty(list, 'skippedListings', { value: 9 });
      return list;
    },
    {
      concurrency: 1,
      pace: {
        perMinute: 18,
        noteHealthy: () => {},
        noteOutcome: (read, failed) => { fed.push([read, failed]); return fed.length === 2; },
      },
    },
  );
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Plano']);
  await scanStateCities(job, 'Car Wash', rec);
  assert.deepEqual(fed, [[1, 9], [1, 9], [1, 9]], 'each city\'s reads and failures reach the pace');
  const warn = job.activityLog.filter((l) => /failing more than usual/.test(l.message));
  assert.equal(warn.length, 1);
  assert.match(warn[0].message, /18\/min/);
});
