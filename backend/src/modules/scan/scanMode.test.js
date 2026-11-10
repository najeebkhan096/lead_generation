import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startStateCityScan, _resetStateCityJobForTests } from './stateCityOrchestrator.js';
import { scrapeOneCity } from './leadService.js';

test('an unknown scan mode is refused before anything starts', async () => {
  _resetStateCityJobForTests();
  await assert.rejects(
    () => startStateCityScan({ categories: ['Plumber'], mode: 'everything', scrapeLocationFn: async () => [] }),
    (err) => err.status === 400 && /mode must be/.test(err.message)
  );
});

const withReviews = (name) => ({
  name,
  category: 'Plumber',
  address: '1 Main St',
  phone: '(512) 555-0100',
  website: null,
  websiteStatus: 'missing',
  mapsUrl: `https://www.google.com/maps/place/${name}`,
  rating: 1.5,
  totalReviews: 40,
  reviews: [{ stars: 1, text: 'Terrible', date: '2 days ago' }],
  source: 'google_maps',
});

test('scrapeOneCity in no_website mode asks the scraper to skip reviews and returns no 1-star leads', async () => {
  let options;
  const result = await scrapeOneCity(
    'Plumber',
    { city: 'Austin', state: 'Texas' },
    {
      mode: 'no_website',
      scrapeLocationFn: async (_c, _l, o) => {
        options = o;
        const list = [withReviews('A'), withReviews('B')];
        Object.defineProperty(list, 'searchStatus', { value: 'ok' });
        return list;
      },
    }
  );
  assert.equal(options.skipReviews, true);
  assert.deepEqual(result.leads, [], 'no review leads in this mode, even if a business had reviews');
  assert.deepEqual(result.reviewIssues, { incomplete: 0, signInBlocked: 0 });
  assert.equal(result.businessesScraped, 2);
  assert.equal(result.siteBusinesses.length, 2, 'the businesses still go to the website classifier');
});

test('scrapeOneCity by default still reads reviews (the 1-star scan is unchanged)', async () => {
  let options;
  await scrapeOneCity(
    'Plumber',
    { city: 'Austin', state: 'Texas' },
    {
      scrapeLocationFn: async (_c, _l, o) => {
        options = o;
        const list = [];
        Object.defineProperty(list, 'searchStatus', { value: 'ok' });
        return list;
      },
    }
  );
  assert.equal(options.skipReviews, false);
});
