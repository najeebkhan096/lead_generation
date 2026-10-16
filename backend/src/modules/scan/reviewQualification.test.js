import { test } from 'node:test';
import assert from 'node:assert/strict';
import { filterRecentOneStarLeads } from './reviewFilter.js';
import { scrapeOneCity } from './leadService.js';

const biz = (over = {}) => ({
  name: 'Test Cafe',
  category: 'Cafe',
  location: 'TX',
  address: '1 Main St, Austin, TX',
  phone: '(415) 555-0100',
  website: 'https://test.example',
  mapsUrl: 'https://www.google.com/maps/place/test-cafe',
  rating: 4.2,
  totalReviews: 120,
  reviews: [],
  source: 'google_maps',
  ...over,
});
const review = (stars, date, reviewer = 'Sam', text = 'text') => ({ stars, date, reviewer, text, link: null });

test('only a 1-star review inside the 28-day window makes a lead', () => {
  const leads = filterRecentOneStarLeads(
    [
      biz({ name: 'In window', reviews: [review(1, '2 weeks ago')] }),
      biz({ name: 'Too old', reviews: [review(1, '2 months ago')] }),
      biz({ name: 'Edge old', reviews: [review(1, '29 days ago')] }),
      biz({ name: 'Not 1 star', reviews: [review(2, '2 days ago'), review(5, '1 day ago')] }),
      biz({ name: 'No reviews', reviews: [] }),
    ],
    { dateRange: '28' },
  );
  assert.deepEqual(leads.map((l) => l.business), ['In window']);
});

test('a business with several qualifying reviews keeps all of them, newest first', () => {
  const [lead] = filterRecentOneStarLeads(
    [biz({ reviews: [review(1, '3 weeks ago', 'Old'), review(1, '2 days ago', 'New'), review(1, '3 months ago', 'Stale')] })],
    { dateRange: '28' },
  );
  assert.equal(lead.badReview.reviewer, 'New');
  assert.deepEqual(lead.allBadReviews.map((r) => r.reviewer), ['New', 'Old']);
});

test('existing rule kept: a very low overall rating (<= 2.2) still qualifies without a recent 1-star', () => {
  const leads = filterRecentOneStarLeads([biz({ rating: 2.0, reviews: [] }), biz({ name: 'Fine', rating: 4.0, reviews: [] })], { dateRange: '28' });
  assert.equal(leads.length, 1);
  assert.equal(leads[0].badReview.date, 'Recent');
});

test('leads keep the existing shape; scraper-only fields (reviewAccess) do not leak into them', () => {
  const [lead] = filterRecentOneStarLeads(
    [biz({ reviews: [review(1, '1 week ago')], reviewAccess: { sorted: false, status: 'signin_required' } })],
    { dateRange: '28' },
  );
  assert.deepEqual(Object.keys(lead).sort(), [
    'address', 'allBadReviews', 'badReview', 'business', 'category', 'id', 'location',
    'mapsUrl', 'phone', 'rating', 'source', 'totalReviews', 'website',
  ]);
  assert.deepEqual(Object.keys(lead.badReview).sort(), ['date', 'link', 'reviewer', 'stars', 'text']);
});

test('duplicate businesses become one lead (existing de-duplication)', async () => {
  const dup = biz({ name: 'Dup Cafe', reviews: [review(1, '2 days ago')] });
  const other = biz({ name: 'Other Cafe', phone: '(415) 555-0199', mapsUrl: 'https://www.google.com/maps/place/other', reviews: [review(1, '1 day ago')] });
  const result = await scrapeOneCity(
    'Cafe',
    { city: 'Austin', state: 'TX' },
    { dateRange: '28', persistWebsiteLeads: false, scrapeLocationFn: async () => [dup, { ...dup }, other] },
  );
  assert.equal(result.businessesScraped, 3);
  assert.equal(result.leads.length, 2);
  assert.deepEqual(result.leads.map((l) => l.business).sort(), ['Dup Cafe', 'Other Cafe']);
});

test('the scan keeps using the 28-day range it is given (no silent widening)', async () => {
  const old = biz({ reviews: [review(1, '2 months ago')] });
  const at28 = await scrapeOneCity('Cafe', { city: 'Austin', state: 'TX' }, { dateRange: '28', persistWebsiteLeads: false, scrapeLocationFn: async () => [old] });
  const at365 = await scrapeOneCity('Cafe', { city: 'Austin', state: 'TX' }, { dateRange: '365', persistWebsiteLeads: false, scrapeLocationFn: async () => [old] });
  assert.equal(at28.leads.length, 0);
  assert.equal(at365.leads.length, 1, 'only an explicit wider range widens it');
});
