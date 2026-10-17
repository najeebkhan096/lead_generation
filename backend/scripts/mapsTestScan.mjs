/**
 * A small, real scan for checking review sorting and the date window:
 *
 *   npm run maps:test-scan -- "Cafe" "Austin, TX" --max 6 --date-range 28
 *
 * For each business it prints how the reviews were read (which sort, whether
 * it was verified, where the reading stopped and whether that proves nothing
 * inside the window was left unread), the first reviews in the order Google
 * returned them, and the 1-star reviews found with whether each is inside the
 * date window. Defaults: 6 businesses, 28 days. Not a production scan: it
 * reads a handful of listings and writes nothing.
 */
import 'dotenv/config';
import { searchBusinesses } from '../src/scraper/googleMapsScraper.js';
import { filterRecentOneStarLeads } from '../src/modules/scan/reviewFilter.js';
import { isWithinRange } from '../src/lib/dateUtils.js';
import { describeSortDiagnostics, resetSortDiagnostics } from '../src/scraper/reviewSort.js';
import { getSessionConfig } from '../src/scraper/mapsSession.js';

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};
const positional = args.filter((a, i) => !a.startsWith('--') && !(args[i - 1] || '').startsWith('--'));
const category = positional[0] || 'Cafe';
const location = positional[1] || 'Austin, TX';
const max = Math.max(1, Math.min(20, Number(flag('max', 6)) || 6));
const dateRange = String(flag('date-range', '28'));

const cfg = getSessionConfig();
console.log(`Scan: "${category}" in ${location} · ${max} businesses · 1-star within ${dateRange} days`);
console.log(`Saved Google session: ${cfg.enabled ? `in use (${cfg.profileDir})` : 'NOT in use (anonymous: reviews cannot be sorted, expect misses)'}\n`);

resetSortDiagnostics();
const notes = [];
const businesses = await searchBusinesses(category, location, {
  maxResults: max,
  dateRange,
  // Keep the messages that explain what was skipped or retried.
  onProgress: (m) => { if (/Skipped|attempt|Found \d+ potential|not fully read|NOT fully/i.test(m)) notes.push(m); },
});

for (const b of businesses) {
  const a = b.reviewAccess || {};
  console.log(`- ${b.name} | rating ${b.rating ?? '?'} | ${b.totalReviews ?? '?'} reviews`);
  console.log(`    read: ${a.complete ? 'COMPLETE' : 'NOT complete'} · strategy ${a.strategy ?? 'none'} · sort [${a.status}] ${a.sorted ? '(verified)' : '(NOT verified)'} · stopped at: ${a.boundary ?? 'n/a'} · ${a.cardsSeen ?? 0} reviews read`);
  if (a.detail) console.log(`    detail: ${a.detail}`);
  console.log(`    first reviews, in the order Google returned them: stars ${JSON.stringify(a.sampleStars ?? [])} dates ${JSON.stringify(a.sampleDates ?? [])}`);
  for (const r of b.reviews) {
    console.log(`    1★ "${(r.text || '').slice(0, 50)}" · ${r.date} · ${isWithinRange(r.date, dateRange) ? `INSIDE ${dateRange}d` : `outside ${dateRange}d (dropped)`}`);
  }
}

for (const n of notes) console.log(`  note: ${n}`);
const leads = filterRecentOneStarLeads(businesses, { dateRange });
const incomplete = businesses.filter((b) => !b.reviewAccess?.complete).length;
console.log(`\nListings skipped after retrying: ${businesses.skippedListings || 0}`);
console.log(`Businesses: ${businesses.length} · fully read: ${businesses.length - incomplete}/${businesses.length} · leads with a 1★ review in the last ${dateRange} days: ${leads.length}`);
console.log(describeSortDiagnostics() || 'No review lookups recorded.');
