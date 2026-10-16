import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scrapeOneCity } from './leadService.js';
import {
  noWebsiteArchiveId,
  noWebsiteFileName,
} from '../archive/excelArchiveStore.js';

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

test('persistWebsiteLeads:false hands no-website businesses back instead of writing them', async () => {
  const result = await scrapeOneCity(
    'cafe',
    { city: 'Austin', state: 'TX' },
    { dateRange: '30', scrapeLocationFn: async () => [noSite], persistWebsiteLeads: false },
  );
  assert.equal(result.websiteLeadsFound, 1);
  assert.equal(result.websiteLeads.length, 1);
  assert.equal(result.websiteLeads[0].business ?? result.websiteLeads[0].name, 'No Site Cafe');
  assert.equal(result.websiteLeads[0].location, 'TX');
});

test('the no-website companion archive id and file name are derived from the review archive', () => {
  assert.equal(noWebsiteArchiveId('abc-123'), 'abc-123-nowebsite');
  assert.equal(noWebsiteFileName('cafe-us-2026-10-16T01-02-03-000Z.xlsx'), 'cafe-us-2026-10-16T01-02-03-000Z-no-website.xlsx');
});
