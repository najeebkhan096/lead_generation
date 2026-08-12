import { scrapeBusinessSnapshot } from '../scraper/googleMapsScraper.js';
import { listWatchlistEntries, getWatchlistEntryRaw, recordScanResult } from './watchlistStore.js';
import { isWithinRange } from '../utils/dateUtils.js';

function reviewKey(review) {
  return `${review.reviewer}|${(review.text || '').slice(0, 80)}`;
}

// Scans every watchlist entry one at a time (a shared browser pool would
// overload this machine's Playwright/Chromium the way concurrent category
// scans already do) and reports which reviews are new since the last scan
// for each business, keyed by reviewer+text since relative date strings
// ("2 months ago") drift and can't identify the same review over time.
// `dateRange` (days, e.g. '30'/'45'/'60') bounds which fetched reviews are
// even considered — older ones are neither reported as new nor kept in the
// dedup baseline, so a business that suddenly surfaces a 2-year-old review
// (Google's sort order isn't perfectly stable) doesn't get flagged.
export async function scanWatchlist({ dateRange = '30' } = {}) {
  const entries = await listWatchlistEntries();
  const results = [];

  for (const entry of entries) {
    const raw = await getWatchlistEntryRaw(entry.id);
    const previousKeys = new Set(raw?.lastReviewKeys || []);
    const isFirstScan = !raw?.lastScannedAt;

    try {
      const snapshot = await scrapeBusinessSnapshot(entry.url, entry.country);
      const recentReviews = snapshot.reviews.filter((r) => isWithinRange(r.date, dateRange));
      const reviewKeys = recentReviews.map(reviewKey);
      const newReviews = isFirstScan
        ? []
        : recentReviews.filter((r) => !previousKeys.has(reviewKey(r)));

      await recordScanResult(entry.id, {
        reviewKeys,
        rating: snapshot.rating,
        totalReviews: snapshot.totalReviews,
        newReviewCount: newReviews.length,
        error: null,
      });

      results.push({
        id: entry.id,
        url: entry.url,
        name: snapshot.name || entry.name,
        rating: snapshot.rating,
        totalReviews: snapshot.totalReviews,
        isFirstScan,
        newReviews,
        error: null,
      });
    } catch (err) {
      const message = err?.message || String(err);
      await recordScanResult(entry.id, {
        reviewKeys: raw?.lastReviewKeys || [],
        rating: raw?.lastRating,
        totalReviews: raw?.lastTotalReviews,
        newReviewCount: 0,
        error: message,
      });
      results.push({
        id: entry.id,
        url: entry.url,
        name: entry.name,
        rating: null,
        totalReviews: null,
        isFirstScan,
        newReviews: [],
        error: message,
      });
    }
  }

  return results;
}
