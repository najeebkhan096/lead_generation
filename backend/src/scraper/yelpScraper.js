/**
 * Fallback scraper: Yelp public search pages (no paid API).
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

  try {
    const findDesc = encodeURIComponent(category);
    const findLoc = encodeURIComponent(location);
    const url = `https://www.yelp.com/search?find_desc=${findDesc}&find_loc=${findLoc}`;
    onProgress?.('Fallback: searching Yelp...');
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(2500);

    const html = await page.content();
    const $ = cheerio.load(html);
    const businesses = [];

    $('a[href*="/biz/"]').each((_, el) => {
      if (businesses.length >= maxResults) return;
      const name = $(el).text().trim();
      const href = $(el).attr('href');
      if (!name || !href || name.length < 2) return;
      if (name.toLowerCase().includes('read more')) return;

      const card = $(el).closest('li, div');
      const ratingText = card.find('[aria-label*="star"]').attr('aria-label') || '';
      const ratingMatch = ratingText.match(/(\d+\.?\d*)/);
      const phone = card.find('[href^="tel:"]').text().trim() || null;

      businesses.push({
        name,
        category,
        location,
        address: location,
        phone,
        website: null,
        mapsUrl: href.startsWith('http') ? href : `https://www.yelp.com${href}`,
        rating: ratingMatch ? Number(ratingMatch[1]) : null,
        totalReviews: null,
        reviews: [],
        source: 'yelp',
      });
    });

    const seen = new Set();
    const unique = businesses.filter((b) => {
      const key = b.name.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });

    onProgress?.(`Yelp fallback found ${unique.length} listings.`);
    return unique.slice(0, maxResults);
  } catch (err) {
    onProgress?.(`Yelp fallback failed: ${err.message}`);
    return [];
  } finally {
    await browser.close();
  }
}
