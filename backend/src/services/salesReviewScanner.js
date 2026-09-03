import { scrapeBusinessSnapshot } from '../scraper/googleMapsScraper.js';
import { isWithinRange } from '../utils/dateUtils.js';
import { listSales, recordSaleReviewScan } from './saleStore.js';

const SCAN_STATUSES = ['new', 'in_progress', 'completed'];

/**
 * Re-scrapes every ongoing (new / in_progress) and completed sale that has
 * a Google Maps review link, looking for 1-star reviews inside `dateRange`
 * days (default 30). Same one-at-a-time Playwright path the watchlist uses
 * so concurrent category scans don't fight this for Chromium.
 *
 * Sales without a review link are reported as skipped rather than failing
 * the whole run — those still need a Maps URL filled in on Manage.
 */
export async function scanSaleReviews({ dateRange = '30', salesmanId } = {}) {
  const sales = await listSales({ salesmanId });
  const targets = sales.filter((s) => SCAN_STATUSES.includes(s.leadStatus));
  const results = [];

  for (const sale of targets) {
    const url = typeof sale.reviewLink === 'string' ? sale.reviewLink.trim() : '';
    if (!url) {
      results.push({
        id: sale.id,
        url: '',
        name: sale.businessName,
        leadStatus: sale.leadStatus,
        rating: null,
        totalReviews: null,
        newReviews: [],
        error: 'No Google Maps review link on this sale',
        skipped: true,
      });
      continue;
    }

    try {
      const snapshot = await scrapeBusinessSnapshot(url, 'US');
      const matches = (snapshot.reviews || []).filter((r) => {
        return r.stars === 1 && isWithinRange(r.date, dateRange);
      });

      await recordSaleReviewScan(sale.id, {
        rating: snapshot.rating,
        totalReviews: snapshot.totalReviews,
        newReviewCount: matches.length,
        error: null,
      });

      results.push({
        id: sale.id,
        url,
        name: snapshot.name || sale.businessName,
        leadStatus: sale.leadStatus,
        rating: snapshot.rating,
        totalReviews: snapshot.totalReviews,
        newReviews: matches,
        error: null,
        skipped: false,
      });
    } catch (err) {
      const message = err?.message || String(err);
      await recordSaleReviewScan(sale.id, {
        rating: null,
        totalReviews: null,
        newReviewCount: 0,
        error: message,
      }).catch(() => {});
      results.push({
        id: sale.id,
        url,
        name: sale.businessName,
        leadStatus: sale.leadStatus,
        rating: null,
        totalReviews: null,
        newReviews: [],
        error: message,
        skipped: false,
      });
    }
  }

  return results;
}
