/**
 * Fallback scraper: Bing Maps / Bing local search public pages.
 */

import { chromium } from 'playwright';
import * as cheerio from 'cheerio';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

export async function searchBusinesses(category, location, { maxResults = 10, onProgress } = {}) {
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const context = await browser.newContext({
    userAgent: USER_AGENT,
    locale: 'en-US',
  });
  const page = await context.newPage();
  const businesses = [];

  try {
    const query = encodeURIComponent(`${category} ${location}`);
    const url = `https://www.bing.com/maps?q=${query}`;
    onProgress?.('Fallback: searching Bing Maps...');
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(3000);

    const html = await page.content();
    const $ = cheerio.load(html);

    // Bing local cards vary; collect name/address-like blocks
    $('[class*="entityTitle"], .b_entityTitle, h2 a, .listings .title').each((_, el) => {
      if (businesses.length >= maxResults) return;
      const name = $(el).text().trim();
      if (!name || name.length < 2) return;

      const parent = $(el).closest('li, div, article');
      const address = parent.find('[class*="address"], .b_address, .b_snippet').first().text().trim();
      const phone = parent.find('[class*="phone"], .b_phone').first().text().trim() || null;

      businesses.push({
        name,
        category,
        location,
        address: address || location,
        phone,
        website: null,
        mapsUrl: `https://www.bing.com/maps?q=${encodeURIComponent(name + ' ' + location)}`,
        rating: null,
        totalReviews: null,
        reviews: [],
        source: 'bing_maps',
      });
    });

    // Deduplicate by name
    const seen = new Set();
    const unique = businesses.filter((b) => {
      const key = b.name.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });

    onProgress?.(`Bing fallback found ${unique.length} listings.`);
    return unique.slice(0, maxResults);
  } catch (err) {
    onProgress?.(`Bing fallback failed: ${err.message}`);
    return [];
  } finally {
    await browser.close();
  }
}
