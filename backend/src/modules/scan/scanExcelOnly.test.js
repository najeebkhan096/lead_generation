import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scrapeOneCity, summarizeReviewAccess } from './leadService.js';

const noSite = {
  name: 'No Site Cafe',
  category: 'cafe',
  address: '2 Main St, Austin, TX',
  phone: '(415) 555-0199',
  website: null,
  mapsUrl: 'https://www.google.com/maps/place/no-site-cafe',
  rating: 4.2,
  totalReviews: 12,
  reviews: [],
  source: 'google_maps',
};

test('businesses with no website are no longer scanned for or returned', async () => {
  const result = await scrapeOneCity('cafe', { city: 'Austin', state: 'TX' }, { dateRange: '28', scrapeLocationFn: async () => [noSite] });
  assert.equal(result.websiteLeadsFound, 0);
  assert.deepEqual(result.websiteLeads, []);
  assert.equal(result.leads.length, 0, 'a business without a 1-star review is not a lead');
  assert.equal(result.businessesScraped, 1);
});

test('the date window is handed to the scraper', async () => {
  let seen;
  await scrapeOneCity('cafe', { city: 'Austin', state: 'TX' }, {
    dateRange: '28',
    scrapeLocationFn: async (_c, _l, opts) => { seen = opts.dateRange; return []; },
  });
  assert.equal(seen, '28');
});

test('review problems are counted per city, split out when Google asked to sign in', () => {
  const ok = { reviewAccess: { complete: true, status: 'ok' } };
  const noRecord = {};
  const unsorted = { reviewAccess: { complete: false, status: 'sort_not_verified' } };
  const blocked = { reviewAccess: { complete: false, status: 'signin_required' } };
  assert.deepEqual(summarizeReviewAccess([ok, noRecord]), { incomplete: 0, signInBlocked: 0 });
  assert.deepEqual(summarizeReviewAccess([ok, unsorted, blocked, blocked]), { incomplete: 3, signInBlocked: 2 });
  assert.deepEqual(summarizeReviewAccess(undefined), { incomplete: 0, signInBlocked: 0 });
});

test('skipped listings reported by the scraper are passed on', async () => {
  const businesses = [noSite];
  Object.defineProperty(businesses, 'skippedListings', { value: 3, enumerable: false });
  const result = await scrapeOneCity('cafe', { city: 'Austin', state: 'TX' }, { dateRange: '28', scrapeLocationFn: async () => businesses });
  assert.equal(result.skippedListings, 3);
});
