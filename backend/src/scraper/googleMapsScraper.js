/**
 * Google Maps public-page scraper via Playwright.
 * Forces hl=en&gl=us so review aria-labels are English ("1 star").
 */

import { chromium } from 'playwright';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

// Google's `gl` param biases which businesses/reviews it considers "local" —
// leaving this hardcoded to `us` was skewing UK/Germany/Canada searches
// toward US-relevant results instead of what's actually near the target city.
const GL_BY_COUNTRY = {
  US: 'us',
  UK: 'gb',
  DE: 'de',
  CA: 'ca',
  IT: 'it',
  FR: 'fr',
  AU: 'au',
  AT: 'at',
  DK: 'dk',
  ES: 'es',
  NL: 'nl',
  BE: 'be',
  CH: 'ch',
  SE: 'se',
};

function glFor(country) {
  return GL_BY_COUNTRY[String(country || 'US').toUpperCase()] || 'us';
}

function buildSearchUrl(category, location, country) {
  const query = encodeURIComponent(`${category} in ${location}`);
  return `https://www.google.com/maps/search/${query}?hl=en&gl=${glFor(country)}`;
}

function withEnglish(url, country) {
  if (!url) return url;
  try {
    const u = new URL(url, 'https://www.google.com');
    u.searchParams.set('hl', 'en');
    u.searchParams.set('gl', glFor(country));
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

export async function launchBrowser() {
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

/**
 * Scrolls the results feed until it stops growing (Google Maps lazy-loads
 * more listings as you near the bottom) or `maxScrolls` is hit, instead of
 * a blind fixed number of scrolls — a city with hundreds of matches keeps
 * loading more, while a small town's feed stops early instead of wasting
 * time scrolling past its actual end.
 */
async function scrollResultsFeed(page, { maxScrolls = 15, stallLimit = 2 } = {}) {
  const feedSelector = 'div[role="feed"], .m67qEc, .section-layout.section-scrollbox';
  const feed = page.locator(feedSelector).first();
  if (!(await feed.count())) return;

  let lastHeight = 0;
  let stalls = 0;
  for (let i = 0; i < maxScrolls; i++) {
    const height = await feed
      .evaluate((el) => {
        el.scrollTop = el.scrollHeight;
        return el.scrollHeight;
      })
      .catch(() => null);
    if (height == null) break;

    await page.waitForTimeout(1000);

    if (height <= lastHeight) {
      stalls += 1;
      if (stalls >= stallLimit) break; // feed has stopped growing — fully loaded
    } else {
      stalls = 0;
    }
    lastHeight = height;
  }
}

/**
 * @param {object} opts
 * @param {import('playwright').Browser} [opts.browser] - reuse an
 *   already-launched browser (e.g. one shared across a worker pool's
 *   categories) instead of launching + closing a fresh process per call.
 *   Each call still gets its own isolated `BrowserContext`, so callers
 *   sharing a browser never share cookies/storage with each other.
 * @param {string} [opts.country] - country code (US/UK/DE/CA) so results
 *   are biased toward that country instead of always the US.
 */
export async function searchBusinesses(category, location, { maxResults = 10, onProgress, browser: sharedBrowser, country = 'US' } = {}) {
  const ownsBrowser = !sharedBrowser;
  const browser = sharedBrowser || (await launchBrowser());
  const context = await createContext(browser);
  const page = await context.newPage();
  const businesses = [];

  try {
    onProgress?.(`Opening Google Maps for "${category}" in ${location}...`);
    await page.goto(buildSearchUrl(category, location, country), {
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

    // Keep scrolling until the feed has enough loaded listings to satisfy
    // maxResults (or stops growing) instead of a fixed handful of scrolls.
    await scrollResultsFeed(page, { maxScrolls: Math.max(15, Math.ceil(maxResults / 2)) });

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
          scrapeOnePlace(placePage, listings[i].href, category, location, country),
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
    await context.close().catch(() => {});
    if (ownsBrowser) await browser.close();
  }

  return businesses;
}

async function scrapeOnePlace(page, href, category, location, country) {
  await page.goto(withEnglish(href, country), { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);
  await dismissConsent(page);
  return extractBusinessFromPlacePage(page, category, location, country);
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

async function extractBusinessFromPlacePage(page, category, location, country) {
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
    mapsUrl: withEnglish(page.url(), country),
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

// Same card/selector logic as extractOneStarReviews, but sorted "Newest"
// and without the 1-star filter — used by the watchlist feature, which
// needs to notice ANY new review (not just qualifying 1-star ones).
async function extractRecentReviews(page, { limit = 10 } = {}) {
  const reviews = [];

  try {
    await page.evaluate(() => {
      const tabs = Array.from(document.querySelectorAll('button[role="tab"], .hh706e button'));
      const reviewTab = tabs.find(t => t.textContent?.toLowerCase().includes('reviews'));
      if (reviewTab) reviewTab.click();
    });
    await page.waitForTimeout(2000);

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
      await page.evaluate(() => {
        const options = Array.from(document.querySelectorAll('[role="menuitem"], [role="menuitemradio"], .fx07Cc'));
        const newest = options.find(o => o.textContent?.toLowerCase().includes('newest'));
        if (newest) newest.click();
      });
      await page.waitForTimeout(2000);
    }

    for (let i = 0; i < 3; i++) {
      await page.mouse.wheel(0, 2000);
      await page.waitForTimeout(500);
    }

    const raw = await page.evaluate((maxCount) => {
      const cards = Array.from(document.querySelectorAll('div.jftiEf, .G5u69c, .W_S_o'));
      const seen = new Set();
      const out = [];

      for (const root of cards) {
        const starEl = root.querySelector('[aria-label*="star" i], .kvS76c, span[role="img"]');
        const aria = starEl?.getAttribute('aria-label') || '';
        const starMatch = aria.match(/(\d+)\s*stars?/i);
        let stars = starMatch ? Number(starMatch[1]) : null;
        if (stars === null) {
          const filledStars = root.querySelectorAll('.vzX5Ic').length;
          if (filledStars > 0) stars = filledStars;
        }

        const reviewer = root.querySelector('.d4r55, .TSZ61d')?.textContent?.trim() || 'Anonymous';
        const date = root.querySelector('.rsqaWe, .DU9u7b')?.textContent?.trim() || 'Unknown';
        const text = root.querySelector('.wiI7hc, .MyEned')?.textContent?.trim() || '';

        // Relative date strings ("2 months ago") drift as time passes, so the
        // dedup/diff key deliberately excludes date — reviewer+text is what
        // actually identifies the same review across repeated scans.
        const key = `${reviewer}|${text.slice(0, 80)}`;
        if (seen.has(key)) continue;
        seen.add(key);

        out.push({ stars, reviewer, text, date });
        if (out.length >= maxCount) break;
      }
      return out;
    }, limit);

    reviews.push(...raw);
  } catch (err) {
    console.error('Error extracting recent reviews:', err);
  }

  return reviews;
}

// Navigates directly to a single business's Maps URL and captures a
// point-in-time snapshot (name, rating, most recent reviews) — used by the
// watchlist feature to detect new reviews on manually-tracked businesses.
export async function scrapeBusinessSnapshot(mapsUrl, country) {
  const browser = await launchBrowser();
  const context = await createContext(browser);
  const page = await context.newPage();
  try {
    await page.goto(withEnglish(mapsUrl, country), { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(1500);

    // Short links (maps.app.goo.gl/...) redirect server-side and drop the
    // hl/gl query params we appended to the pre-redirect URL — the page
    // that actually loads can come back in whatever locale Google
    // defaults to (observed: Arabic, regardless of Accept-Language),
    // which then silently breaks every English-text-matching selector
    // below (the "Reviews" tab, "Sort" menu, etc.) and returns zero
    // reviews with no error. Detect that and reload with hl/gl forced
    // onto the real, post-redirect URL.
    if (!/[?&]hl=en(&|$)/.test(page.url())) {
      await page.goto(withEnglish(page.url(), country), { waitUntil: 'domcontentloaded', timeout: 45000 });
      await page.waitForTimeout(1500);
    }

    await dismissConsent(page);

    const name = await textOrNull(page, ['h1.DUwDvf', 'h1']);

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

    const reviews = await extractRecentReviews(page, { limit: 10 });

    return {
      name,
      mapsUrl: withEnglish(page.url(), country),
      rating,
      totalReviews,
      reviews,
    };
  } finally {
    await browser.close();
  }
}
