/**
 * Google Maps public-page scraper via Playwright.
 * Forces hl=en&gl=us so review aria-labels are English ("1 star").
 */

import { chromium } from 'playwright';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

function buildSearchUrl(category, location) {
  const query = encodeURIComponent(`${category} in ${location}`);
  return `https://www.google.com/maps/search/${query}?hl=en&gl=us`;
}

function withEnglish(url) {
  if (!url) return url;
  try {
    const u = new URL(url, 'https://www.google.com');
    u.searchParams.set('hl', 'en');
    u.searchParams.set('gl', 'us');
    return u.toString();
  } catch {
    return url;
  }
}

async function withTimeout(promise, ms, label = 'operation') {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function launchBrowser() {
  return chromium.launch({
    headless: true,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--lang=en-US',
      '--disable-setuid-sandbox',
      '--disable-infobars',
      '--window-position=0,0',
      '--ignore-certifcate-errors',
      '--ignore-certifcate-errors-spki-list',
    ],
  });
}

async function createContext(browser) {
  return browser.newContext({
    userAgent: USER_AGENT,
    locale: 'en-US',
    extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9' },
    viewport: { width: 1366, height: 900 },
  });
}

async function dismissConsent(page) {
  try {
    // Look for anything that looks like a big "Accept" button
    await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button'));
      const accept = buttons.find(b => {
        const text = (b.textContent || '').toLowerCase();
        return text.includes('accept all') ||
               text.includes('i agree') ||
               text.includes('agree') ||
               text.includes('accept');
      });
      if (accept) accept.click();
    });
    await page.waitForTimeout(1000);
  } catch {
    // ignore
  }
}

async function scrollResultsFeed(page, maxScrolls = 5) {
  const feed = page.locator('div[role="feed"]').first();
  if (!(await feed.count())) return;
  for (let i = 0; i < maxScrolls; i++) {
    await feed.evaluate((el) => {
      el.scrollTop = el.scrollHeight;
    }).catch(() => {});
    await page.waitForTimeout(600);
  }
}

export async function searchBusinesses(category, location, { maxResults = 10, onProgress } = {}) {
  const browser = await launchBrowser();
  const context = await createContext(browser);
  const page = await context.newPage();
  const businesses = [];

  try {
    onProgress?.(`Opening Google Maps for "${category}" in ${location}...`);
    await page.goto(buildSearchUrl(category, location), {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    await page.waitForTimeout(2500);
    await dismissConsent(page);

    try {
      // Wait for any listing-like link or the feed container
      await page.waitForSelector('a[href*="/maps/place"], [role="feed"], .m67qEc', { timeout: 25000 });
    } catch {
      onProgress?.('No results found. Google might be showing a different layout or blocking the request.');
      return businesses;
    }

    // Try to find the scrollable container more broadly
    await page.evaluate(async () => {
      const feed = document.querySelector('div[role="feed"]') ||
                   document.querySelector('.m67qEc') ||
                   document.querySelector('.section-layout.section-scrollbox');
      if (feed) {
        for (let i = 0; i < 3; i++) {
          feed.scrollTop = feed.scrollHeight;
          await new Promise(r => setTimeout(r, 800));
        }
      }
    });

    const listings = await page.evaluate(() => {
      const seen = new Set();
      const out = [];
      // Look for all links that look like place listings
      const links = Array.from(document.querySelectorAll('a[href*="/maps/place"]'));
      for (const a of links) {
        const href = a.href;
        if (!href || seen.has(href)) continue;
        // Avoid clicking mini-links inside a result (like "Website" or "Directions")
        const nameEl = a.querySelector('div.fontHeadlineSmall');
        const ariaLabel = a.getAttribute('aria-label');
        if (nameEl || ariaLabel) {
          seen.add(href);
          out.push({ href, name: (nameEl?.textContent || ariaLabel || '').trim() });
        }
      }
      return out;
    });

    onProgress?.(`Found ${listings.length} potential businesses.`);
    if (!listings.length) return businesses;

    const limit = Math.min(listings.length, maxResults);

    for (let i = 0; i < limit; i++) {
      const placePage = await context.newPage();
      const listingName = listings[i].name;
      try {
        onProgress?.(
          `Opening listing ${i + 1}/${limit}${listingName ? `: ${listingName}` : ''}...`
        );
        const business = await withTimeout(
          scrapeOnePlace(placePage, listings[i].href, category, location),
          45000,
          `place ${i + 1}`
        );
        if (business?.name) {
          businesses.push(business);
          onProgress?.(
            `Collected: ${business.name} (${business.reviews.length}× 1★) [${businesses.length}/${limit}]`
          );
        }
      } catch (err) {
        onProgress?.(`Skipped listing ${i + 1}: ${err.message}`);
      } finally {
        await placePage.close().catch(() => {});
      }
    }
  } finally {
    await browser.close();
  }

  return businesses;
}

async function scrapeOnePlace(page, href, category, location) {
  await page.goto(withEnglish(href), { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);
  await dismissConsent(page);
  return extractBusinessFromPlacePage(page, category, location);
}

async function textOrNull(page, selectors) {
  for (const selector of selectors) {
    try {
      const el = page.locator(selector).first();
      if ((await el.count()) === 0) continue;
      const text = (await el.innerText({ timeout: 1500 })).trim();
      if (text) return text;
    } catch {
      // continue
    }
  }
  return null;
}

async function extractBusinessFromPlacePage(page, category, location) {
  const name = await textOrNull(page, ['h1.DUwDvf', 'h1']);
  if (!name) return null;

  let rating = null;
  try {
    const ratingLabel = await page.locator('[aria-label*="stars"]').first().getAttribute('aria-label', { timeout: 2000 });
    const m = ratingLabel?.match(/(\d+\.?\d*)\s*stars?/i);
    if (m) rating = Number(m[1]);
  } catch {
    // ignore
  }

  let totalReviews = null;
  try {
    const reviewsLabel = await page
      .locator('button[aria-label*="reviews"]')
      .first()
      .getAttribute('aria-label', { timeout: 2000 });
    const m = reviewsLabel?.replace(/,/g, '').match(/(\d+)\s*reviews?/i);
    if (m) totalReviews = Number(m[1]);
  } catch {
    // ignore
  }

  const address = await textOrNull(page, [
    'button[data-item-id="address"]',
    'button[aria-label*="Address"]',
  ]);
  const phone = await textOrNull(page, [
    'button[data-item-id^="phone"]',
    'button[aria-label*="Phone"]',
  ]);

  let website = null;
  try {
    website = await page
      .locator('a[data-item-id="authority"], a[aria-label*="Website"]')
      .first()
      .getAttribute('href', { timeout: 1500 });
  } catch {
    // ignore
  }

  const reviews = await extractOneStarReviews(page);

  return {
    name,
    category,
    location,
    address: address || location,
    phone: phone || null,
    website: website || null,
    mapsUrl: withEnglish(page.url()),
    rating,
    totalReviews,
    reviews,
    source: 'google_maps',
  };
}

async function extractOneStarReviews(page) {
  const reviews = [];

  try {
    // 1. Click the "Reviews" tab
    await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button[role="tab"], .hh706e button'));
      const reviewTab = tabs.find(t => t.textContent?.toLowerCase().includes('reviews'));
      if (reviewTab) reviewTab.click();
    });
    await page.waitForTimeout(2000);

    // 2. Click Sort button
    const sortClicked = await page.evaluate(() => {
      const buttons = Array.from(document.querySelectorAll('button[aria-label*="Sort"], button.g67oK'));
      const sortBtn = buttons.find(b => {
        const txt = (b.getAttribute('aria-label') || b.textContent || '').toLowerCase();
        return txt.includes('sort');
      });
      if (sortBtn) {
        sortBtn.click();
        return true;
      }
      return false;
    });

    if (sortClicked) {
      await page.waitForTimeout(1000);
      // 3. Select "Lowest rating"
      await page.evaluate(() => {
        const options = Array.from(document.querySelectorAll('[role="menuitem"], [role="menuitemradio"], .fx07Cc'));
        const lowest = options.find(o => o.textContent?.toLowerCase().includes('lowest'));
        if (lowest) lowest.click();
      });
      await page.waitForTimeout(2000);
    }

    // Scroll a bit to load reviews
    for (let i = 0; i < 3; i++) {
      await page.mouse.wheel(0, 2000);
      await page.waitForTimeout(500);
    }

    const raw = await page.evaluate(() => {
      // Common review card classes
      const cards = Array.from(document.querySelectorAll('div.jftiEf, .G5u69c, .W_S_o'));
      const seen = new Set();
      const out = [];

      for (const root of cards) {
        // Try multiple ways to find stars
        const starEl = root.querySelector('[aria-label*="star" i], .kvS76c, span[role="img"]');
        const aria = starEl?.getAttribute('aria-label') || '';
        const starMatch = aria.match(/(\d+)\s*stars?/i);

        let stars = starMatch ? Number(starMatch[1]) : null;
        if (stars === null) {
          // Fallback check for visual stars if aria-label fails
          const filledStars = root.querySelectorAll('.vzX5Ic').length; // Some themes
          if (filledStars > 0) stars = filledStars;
        }

        if (stars !== 1) continue;

        const reviewer = root.querySelector('.d4r55, .TSZ61d')?.textContent?.trim() || 'Anonymous';
        const date = root.querySelector('.rsqaWe, .DU9u7b')?.textContent?.trim() || 'Unknown';
        const text = root.querySelector('.wiI7hc, .MyEned')?.textContent?.trim() || '';

        const key = `${reviewer}|${date}|${text.slice(0, 50)}`;
        if (seen.has(key)) continue;
        seen.add(key);

        out.push({ stars: 1, reviewer, text, date });
        if (out.length >= 15) break;
      }
      return out;
    });

    reviews.push(...raw);
  } catch (err) {
    console.error('Error extracting reviews:', err);
  }

  return reviews;
}

export async function scrapePlaceReviews(mapsUrl) {
  const browser = await launchBrowser();
  const context = await createContext(browser);
  const page = await context.newPage();
  try {
    await page.goto(withEnglish(mapsUrl), { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(2000);
    await dismissConsent(page);
    return extractOneStarReviews(page);
  } finally {
    await browser.close();
  }
}
