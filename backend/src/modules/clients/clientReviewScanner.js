import { scrapeBusinessSnapshot } from '../../scraper/googleMapsScraper.js';
import { isWithinRange } from '../../lib/dateUtils.js';
import { listClients } from './clientStore.js';

/**
 * Loads every stored client's Google Maps page (one at a time, the same
 * Playwright path the watchlist and sales scans use) and collects the 1-star
 * reviews posted inside `dateRange` days. A client with no link, or whose page
 * fails to load, is reported rather than failing the run.
 *
 * Result rows share the sales scan's shape so the web app renders both alike.
 */
export async function scanClientReviews({ dateRange = '28' } = {}) {
  const clients = await listClients();
  const results = [];

  for (const client of clients) {
    const url = typeof client.mapsUrl === 'string' ? client.mapsUrl.trim() : '';
    const base = { id: client.id, url, name: client.businessName, leadStatus: null };

    if (!url) {
      results.push({
        ...base,
        rating: null,
        totalReviews: null,
        newReviews: [],
        error: 'No Google Maps link on this client',
        skipped: true,
      });
      continue;
    }

    try {
      const snapshot = await scrapeBusinessSnapshot(url, 'US', { dateRange });
      const matches = (snapshot.reviews || []).filter((r) => r.stars === 1 && isWithinRange(r.date, dateRange));
      const access = snapshot.reviewAccess;
      if (!matches.length && access && !access.complete) {
        // The reviews could not be proven fully read (Google would not let them
        // be sorted, or reading stopped early), so "no 1-star reviews found"
        // would be a guess. Say so instead of reporting clean.
        results.push({
          ...base,
          name: snapshot.name || client.businessName,
          rating: snapshot.rating,
          totalReviews: snapshot.totalReviews,
          newReviews: [],
          error: `Reviews could not be read completely (${access.status}), so this client could not be fully checked`,
          skipped: false,
        });
        continue;
      }
      results.push({
        ...base,
        name: snapshot.name || client.businessName,
        rating: snapshot.rating,
        totalReviews: snapshot.totalReviews,
        newReviews: matches,
        error: null,
        skipped: false,
      });
    } catch (err) {
      results.push({
        ...base,
        rating: null,
        totalReviews: null,
        newReviews: [],
        error: err?.message || String(err),
        skipped: false,
      });
    }
  }

  return results;
}
