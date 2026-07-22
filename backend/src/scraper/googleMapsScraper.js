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
  for (const selector of [
    'button:has-text("Accept all")',
    'button:has-text("Accept")',
    'button:has-text("I agree")',
    'button[aria-label="Accept all"]',
  ]) {
    try {
      const btn = page.locator(selector).first();
      if (await btn.isVisible({ timeout: 800 })) {
        await btn.click({ timeout: 1500 });
        await page.waitForTimeout(500);
        return;
      }
    } catch {
      // ignore
    }
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
      await page.waitForSelector('div[role="feed"], a[href*="/maps/place"]', { timeout: 25000 });
    } catch {
      onProgress?.('No results feed found on Google Maps.');
      return businesses;
    }

    await scrollResultsFeed(page);

    const hrefs = await page.locator('div[role="feed"] a[href*="/maps/place"]').evaluateAll((as) => {
      const seen = new Set();
      const out = [];
      for (const a of as) {
        if (!a.href || seen.has(a.href)) continue;
        seen.add(a.href);
        out.push(a.href);
      }
      return out;
    });

    onProgress?.(`Found ${hrefs.length} business listings.`);
    if (!hrefs.length) return businesses;

    const limit = Math.min(hrefs.length, maxResults);

    for (let i = 0; i < limit; i++) {
      const placePage = await context.newPage();
      try {
        onProgress?.(`Opening listing ${i + 1}/${limit}...`);
        const business = await withTimeout(
          scrapeOnePlace(placePage, hrefs[i], category, location),
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
    // Click Reviews — prefer button with review count in aria-label
    const clicked = await page.evaluate(() => {
      const candidates = [
        ...document.querySelectorAll('button, div[role="tab"], button[role="tab"]'),
      ];
      for (const el of candidates) {
        const label = `${el.getAttribute('aria-label') || ''} ${el.textContent || ''}`.toLowerCase();
        if (label.includes('review')) {
          el.click();
          return label.slice(0, 80);
        }
      }
      return null;
    });
    if (clicked) await page.waitForTimeout(1500);

    // Sort by lowest rating via DOM (avoids Playwright locator hangs)
    await page.evaluate(() => {
      const buttons = [...document.querySelectorAll('button')];
      const sort = buttons.find((b) => /sort/i.test(b.getAttribute('aria-label') || b.textContent || ''));
      if (sort) sort.click();
    });
    await page.waitForTimeout(600);
    await page.evaluate(() => {
      const items = [...document.querySelectorAll('[role="menuitemradio"], [role="menuitem"]')];
      const lowest = items.find((el) => /lowest/i.test(el.textContent || ''));
      if (lowest) lowest.click();
    });
    await page.waitForTimeout(1500);

    for (let i = 0; i < 5; i++) {
      await page.mouse.wheel(0, 1600);
      await page.waitForTimeout(400);
    }

    const raw = await page.evaluate(() => {
      const cards = [...document.querySelectorAll('div.jftiEf')];
      const seen = new Set();
      const out = [];

      for (const root of cards) {
        const aria =
          root.querySelector('[aria-label*="star" i]')?.getAttribute('aria-label') ||
          root.querySelector('span[role="img"]')?.getAttribute('aria-label') ||
          '';
        const starMatch = aria.match(/(\d+)\s*stars?/i);
        if (!starMatch || Number(starMatch[1]) !== 1) continue;

        const reviewer = root.querySelector('div.d4r55')?.textContent?.trim() || null;
        const date =
          root.querySelector('span.rsqaWe')?.textContent?.trim() ||
          root.querySelector('span[class*="rsqa"]')?.textContent?.trim() ||
          'Unknown';
        const text =
          root.querySelector('span.wiI7hc')?.textContent?.trim() ||
          root.querySelector('span[class*="wiI7"]')?.textContent?.trim() ||
          '';

        const key = `${reviewer}|${date}|${text.slice(0, 60)}`;
        if (seen.has(key)) continue;
        seen.add(key);

        out.push({ stars: 1, reviewer, text, date });
        if (out.length >= 20) break;
      }
      return out;
    });

    reviews.push(...raw);
  } catch {
    // optional
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
