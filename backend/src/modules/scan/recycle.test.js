import { test } from 'node:test';
import assert from 'node:assert/strict';
import { _scanStateCities as scanStateCities, _newStateRecord as newStateRecord, _recycleWhenDue as recycleWhenDue, _recycleStateFor as recycleStateFor } from './stateCityOrchestrator.js';

const oneStarBusiness = (name) => ({
  name,
  category: 'Car Wash',
  address: '1 Main St',
  phone: '(415) 555-0100',
  mapsUrl: `https://www.google.com/maps/place/${encodeURIComponent(name)}`,
  rating: 4,
  totalReviews: 50,
  reviews: [{ stars: 1, reviewer: 'Sam', date: '2 days ago', text: 'bad', link: null }],
  reviewAccess: { complete: true, status: 'ok', sorted: true },
  source: 'google_maps',
});

function makeJob(scrapeLocationFn, extra = {}) {
  return {
    concurrency: 1,
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

test('the shared browser is replaced after every few cities, even inside one long state', async () => {
  const job = makeJob(async (_c, location) => [oneStarBusiness(`Wash ${location}`)], { recycleEveryCities: 2 });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Houston']);
  await scanStateCities(job, 'Car Wash', rec);

  assert.equal(rec.status, 'done');
  // Due after the second city, replaced before the third; the third leaves it not yet due.
  assert.equal(job.recycle.recycles, 1);
});

test('a due recycle waits until no worker is in the middle of a city', async () => {
  const job = makeJob(async () => []);
  const rc = recycleStateFor(job);
  rc.due = true;
  rc.inFlight = 1;
  await recycleWhenDue(job);
  assert.equal(rc.recycles, 0, 'not replaced while a city is in flight');
  assert.equal(rc.due, true);

  rc.inFlight = 0;
  await recycleWhenDue(job);
  assert.equal(rc.recycles, 1);
  assert.equal(rc.due, false);
});
