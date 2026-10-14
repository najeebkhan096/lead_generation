import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { scrapeOneCity } from './leadService.js';

/**
 * Scanning is lead discovery only. WhatsApp validation (WhatsApp Web, its
 * safety limits, its job) runs solely when the user starts it from the Leads
 * page, so nothing reachable from the scan may import it.
 */

const here = path.dirname(fileURLToPath(import.meta.url));
const ENTRY = path.join(here, 'stateCityScanController.js');

// Anything that opens WhatsApp Web, spends its rate limit, or stores results.
const FORBIDDEN = [
  'whatsappWebService',
  'whatsappSafety',
  'whatsappValidationJob',
  'whatsappWebController',
  'whatsappLeadStore',
  'whatsappValidatedStore',
  'whatsapp-web.js',
];

function importsOf(file) {
  const src = fs.readFileSync(file, 'utf8');
  // `from 'x'`, `import('x')` and bare side-effect `import 'x'`.
  return [...src.matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+)['"]([^'"]+)['"]/g)].map((m) => m[1]);
}

/** Every file reachable from `entry` through relative imports, plus bare package names. */
function reachable(entry) {
  const files = new Set();
  const packages = new Set();
  const queue = [entry];
  while (queue.length) {
    const file = queue.pop();
    if (files.has(file)) continue;
    files.add(file);
    for (const spec of importsOf(file)) {
      if (spec.startsWith('.')) queue.push(path.resolve(path.dirname(file), spec));
      else packages.add(spec);
    }
  }
  return { files, packages };
}

test('the scan call chain never imports the WhatsApp validation modules', () => {
  const { files, packages } = reachable(ENTRY);

  // Sanity: the walk really covers the scan engine, the scraper and the stores.
  const names = [...files].map((f) => path.basename(f));
  for (const expected of ['stateCityOrchestrator.js', 'leadService.js', 'googleMapsScraper.js', 'firebaseLeadStore.js']) {
    assert.ok(names.includes(expected), `${expected} should be reachable from the scan controller`);
  }

  const hits = [...files, ...packages].filter((x) => FORBIDDEN.some((f) => String(x).includes(f)));
  assert.deepEqual(hits, [], 'scan must not reach WhatsApp validation');
});

test('scraping a city yields leads with a wa.me link but no WhatsApp check', async () => {
  const business = {
    name: 'Joe Plumbing',
    category: 'plumber',
    address: '1 Main St, Austin, TX',
    phone: '(415) 555-0100',
    website: 'https://joeplumbing.example', // has a site: keeps this test off Firestore
    mapsUrl: 'https://www.google.com/maps/place/joe-plumbing',
    rating: 3.1,
    totalReviews: 40,
    reviews: [{ stars: 1, reviewer: 'Sam', date: '2 days ago', text: 'Never showed up', link: null }],
    source: 'google_maps',
  };
  const ready = [];
  const result = await scrapeOneCity(
    'plumber',
    { city: 'Austin', state: 'TX' },
    {
      dateRange: '30',
      scrapeLocationFn: async () => [business],
      onLeadReady: async (lead) => { ready.push(lead); },
    },
  );

  assert.equal(result.leads.length, 1);
  assert.equal(result.businessesScraped, 1);
  assert.equal(ready.length, 1);

  const lead = ready[0];
  assert.equal(lead.phone, '+14155550100');
  assert.match(lead.waLink, /^https:\/\/wa\.me\/14155550100/);
  assert.equal(lead.hasWhatsApp, false);
  assert.equal(lead.whatsAppCheckedAt, undefined);
});
