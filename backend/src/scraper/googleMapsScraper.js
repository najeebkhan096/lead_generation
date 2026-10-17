/**
 * Google Maps public-page scraper via Playwright.
 * Forces hl=en&gl=us so review aria-labels are English ("1 star").
 */

import { chromium } from 'playwright';
import { getSessionConfig, profileExists, launchSessionBrowser, probeSignedIn } from './mapsSession.js';
import { GoogleBlockedError, throwIfBlocked } from './googleBlock.js';
import { placeIdFromHref } from '../lib/placeId.js';
import { sharedPace } from './rateLimit.js';
import {
  SORT_STATUS,
  isSortSuccess,
  setSessionMode,
  readOneStarCount,
  openReviewsPanel,
  sortLowestFirst,
  sortReviewsWithRetry,
  loadReviewsToBoundary,
  scrollReviewPanel,
  readReviewCards,
} from './reviewSort.js';

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

function buildSearchUrl(category, location, country, center) {
  if (center) {
    // Search the map around a point (a grid cell of a large city) instead of by place name.
    const zoom = center.zoom || 14;
    return `https://www.google.com/maps/search/${encodeURIComponent(category)}/@${center.lat},${center.lng},${zoom}z?hl=en&gl=${glFor(country)}`;
  }
  const query = encodeURIComponent(`${category} in ${location}`);
  return `https://www.google.com/maps/search/${query}?hl=en&gl=${glFor(country)}`;
}

/**
 * True when a business PROVABLY has no 1-star review, from the rating and
 * review count Google shows beside it in the result list, so its page need not
 * be opened. The displayed rating r is the average, rounded to 0.1, so the true
 * average is at least r - 0.05; with k one-star reviews among n the average is
 * at most 5 - 4k/n. A 1-star review is therefore possible only if
 * n * (5 - r + 0.05) >= 4. Exact, not a guess: nothing it skips could have
 * held a lead. (Unknown rating or count: never skipped.)
 */
export function cannotHaveOneStar(rating, reviews) {
  if (reviews === 0) return true;
  if (!Number.isFinite(rating) || !Number.isFinite(reviews) || reviews < 0) return false;
  return reviews * (5 - rating + 0.05) < 4;
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

export { placeIdFromHref };

/** Rejects as soon as `shouldStop()` turns true, so a cancel is not stuck behind a slow page. */
function raceWithCancel(promise, shouldStop) {
  if (!shouldStop) return promise;
  let timer;
  const cancelled = new Promise((_, reject) => {
    timer = setInterval(() => {
      if (shouldStop()) reject(new Error('cancelled'));
    }, 500);
  });
  return Promise.race([promise, cancelled]).finally(() => clearInterval(timer));
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

export const BROWSER_ARGS = [
  '--disable-blink-features=AutomationControlled',
  '--no-sandbox',
  '--disable-dev-shm-usage',
  '--lang=en-US',
  '--disable-setuid-sandbox',
  '--disable-infobars',
  '--window-position=0,0',
  '--ignore-certifcate-errors',
  '--ignore-certifcate-errors-spki-list',
];

export const CONTEXT_OPTIONS = {
  userAgent: USER_AGENT,
  locale: 'en-US',
  extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9' },
  viewport: { width: 1366, height: 900 },
};

// A listing gets this long (reading every review in the window can take a
// while on a busy place) and is tried this many times before it is given up on.
const PLACE_TIMEOUT_MS = 70000;
const PLACE_ATTEMPTS = 2;

// How many scraper browsers currently hold the saved profile (a profile can
// only be open in one browser, so signing in must wait for these to close).
let openSessionBrowsers = 0;
export function isSessionProfileInUse() {
  return openSessionBrowsers > 0;
}

let warnedSessionFallback = false;
function warnSessionFallback(message) {
  if (warnedSessionFallback) return;
  warnedSessionFallback = true;
  console.warn(`[maps] ${message} Continuing without a saved Google session.`);
}

/**
 * Launches the scraper's browser. With MAPS_PERSISTENT_SESSION on and a saved
 * profile (see scripts/mapsLogin.mjs) it reuses that signed-in profile;
 * otherwise, or if the profile cannot be opened (missing, or open in another
 * process), it launches the usual anonymous browser. Never throws because of
 * the session.
 */
export async function launchBrowser() {
  const cfg = getSessionConfig();
  setSessionMode(false);
  if (cfg.enabled) {
    if (!profileExists(cfg.profileDir)) {
      warnSessionFallback(`MAPS_PERSISTENT_SESSION is on but there is no saved profile at ${cfg.profileDir}; run \`npm run maps:login\`.`);
    } else {
      try {
        const browser = await launchSessionBrowser({
          chromium,
          profileDir: cfg.profileDir,
          channel: cfg.channel,
          args: BROWSER_ARGS,
          contextOptions: CONTEXT_OPTIONS,
          chromePath: cfg.chromePath || undefined,
          // MAPS_HEADFUL=true shows the Chrome window while scanning.
          headless: !/^(1|true|yes|on)$/i.test(process.env.MAPS_HEADFUL || ''),
        });
        setSessionMode(true);
        openSessionBrowsers += 1;
        const close = browser.close;
        let closed = false;
        browser.close = async () => {
          if (!closed) {
            closed = true;
            openSessionBrowsers -= 1;
          }
          await close();
        };
        return browser;
      } catch (err) {
        warnSessionFallback(`Could not open the saved Google session (${(err?.message || String(err)).split('\n')[0]}).`);
      }
    }
  }
  return chromium.launch({ headless: true, args: BROWSER_ARGS });
}

/**
 * Whether the scraper's browser is signed in to Google:
 * 'anonymous' (no saved session in use), or 'signed_in' / 'signed_out' /
 * 'unknown' for a saved session. Opens Maps once to look.
 */
export async function checkBrowserSignedIn(browser) {
  if (!browser?.isSession) return { status: 'anonymous' };
  const context = await createContext(browser);
  const page = await context.newPage();
  try {
    return { status: await probeSignedIn(page) };
  } finally {
    await page.close().catch(() => {});
  }
}

async function createContext(browser) {
  return browser.newContext(CONTEXT_OPTIONS);
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
/**
 * Searches Google Maps for `category` in `location` and reads each listing.
 *
 * The returned array carries (non-enumerable) facts about the search itself:
 *   searchStatus      'ok' | 'no_results' (Google genuinely found nothing) |
 *                     'feed_missing' (no result list appeared: a layout change
 *                     or a page that is not results, NOT an empty city)
 *   listingsFound     listings in the result list
 *   duplicatesSkipped listings already read for another city (`seenPlaceIds`)
 *   skippedListings   listings that could not be opened even after retrying
 * Throws GoogleBlockedError when Google shows its "unusual traffic" check.
 *
 * @param {Set<string>} [seenPlaceIds] place ids already read in this scan: a
 *   business listed by several neighbouring cities is read once.
 */
export async function searchBusinesses(category, location, {
  maxResults = 10,
  onProgress,
  browser: sharedBrowser,
  country = 'US',
  shouldStop,
  dateRange = '28',
  seenPlaceIds,
  center,
  feedTimeoutMs = 15000,
  pace = sharedPace(),
} = {}) {
  const ownsBrowser = !sharedBrowser;
  const browser = sharedBrowser || (await launchBrowser());
  const context = await createContext(browser);
  const page = await context.newPage();
  const businesses = [];
  const meta = { searchStatus: 'ok', listingsFound: 0, duplicatesSkipped: 0, skippedListings: 0, prefiltered: 0 };

  try {
    onProgress?.(`Opening Google Maps for "${category}" in ${location}...`);
    await page.goto(buildSearchUrl(category, location, country, center), {
      waitUntil: 'domcontentloaded',
      timeout: 60000,
    });
    await page.waitForTimeout(2500);
    await throwIfBlocked(page);
    await dismissConsent(page);

    try {
      // Wait for any listing-like link or the feed container
      await page.waitForSelector('a[href*="/maps/place"], [role="feed"], .m67qEc', { timeout: feedTimeoutMs });
    } catch {
      // Not an empty city: no result list appeared at all. It may be Google's
      // check (then this throws), otherwise a layout change or a slow page.
      await throwIfBlocked(page);
      // Google says so in words when a search genuinely has nothing.
      const saysNothing = await page
        .getByText(/can.?t find|no results found|did not match any/i)
        .first()
        .isVisible({ timeout: 500 })
        .catch(() => false);
      meta.searchStatus = saysNothing ? 'no_results' : 'feed_missing';
      onProgress?.(
        saysNothing
          ? 'Google found no results for this search.'
          : 'Google returned no result list for this search (not the same as "no results").'
      );
      return businesses;
    }

    // Keep scrolling until the feed has enough loaded listings to satisfy
    // maxResults (or stops growing) instead of a fixed handful of scrolls.
    await scrollResultsFeed(page, { maxScrolls: Math.max(15, Math.ceil(maxResults / 2)) });

    const listings = await page.evaluate(() => {
      const seen = new Set();
      const out = [];
      const num = (t) => {
        const n = Number(String(t).replace(/[^\d.]/g, ''));
        return Number.isFinite(n) && String(t).trim() !== '' ? n : null;
      };
      // The rating and review count Google shows on the result card.
      const cardFacts = (a) => {
        const card = a.closest('[role="article"]') || a.parentElement?.parentElement || a.parentElement;
        if (!card) return { rating: null, reviews: null };
        for (const el of card.querySelectorAll('[aria-label]')) {
          const m = (el.getAttribute('aria-label') || '').match(/(\d(?:\.\d)?)\s*stars?\s+([\d,]+)\s*reviews?/i);
          if (m) return { rating: Number(m[1]), reviews: Number(m[2].replace(/,/g, '')) };
        }
        const r = card.querySelector('.MW4etd');
        const c = card.querySelector('.UY7F9');
        return { rating: r ? num(r.textContent) : null, reviews: c ? num(c.textContent) : null };
      };
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
          out.push({ href, name: (nameEl?.textContent || ariaLabel || '').trim(), ...cardFacts(a) });
        }
      }
      return out;
    });

    meta.listingsFound = listings.length;
    onProgress?.(`Found ${listings.length} potential businesses.`);
    if (!listings.length) {
      // A result list was there but empty: Google genuinely found nothing.
      meta.searchStatus = (await page.locator('[role="feed"]').count()) ? 'no_results' : 'feed_missing';
      return businesses;
    }

    // A business listed by several neighbouring cities is read once: claim each
    // place id now, so concurrent cities do not both read it.
    const fresh = [];
    for (const l of listings) {
      // Provably no 1-star review (from the card's rating and count): nothing to read.
      if (cannotHaveOneStar(l.rating, l.reviews)) {
        meta.prefiltered += 1;
        continue;
      }
      const id = placeIdFromHref(l.href);
      if (id && seenPlaceIds) {
        if (seenPlaceIds.has(id)) {
          meta.duplicatesSkipped += 1;
          continue;
        }
        seenPlaceIds.add(id);
      }
      fresh.push({ ...l, id });
    }
    if (meta.duplicatesSkipped) onProgress?.(`${meta.duplicatesSkipped} already read for another city.`);
    if (meta.prefiltered) onProgress?.(`${meta.prefiltered} cannot have a 1-star review (from their rating and review count).`);

    const limit = Math.min(fresh.length, maxResults);
    let skippedListings = 0;

    for (let i = 0; i < limit; i++) {
      // Checked between listings, not mid-listing — a cancel takes effect
      // as soon as whatever's currently open finishes, same granularity as
      // every other stop point in this app, instead of running the full
      // `maxResults` listings regardless (which, at higher maxResults
      // settings, could make Cancel appear to do nothing for a long time).
      if (shouldStop?.()) {
        onProgress?.('Stopped — cancelled.');
        break;
      }
      const listingName = fresh[i].name;
      let business = null;
      let lastError = null;
      // A listing that times out or fails once is tried again on a fresh page;
      // silently dropping it would be a business (and its reviews) missed.
      for (let attempt = 1; attempt <= PLACE_ATTEMPTS && !business; attempt++) {
        if (shouldStop?.()) break;
        // One shared pace for every worker: stay under the requests-per-minute budget.
        await pace.acquire();
        const placePage = await context.newPage();
        try {
          onProgress?.(
            `Opening listing ${i + 1}/${limit}${listingName ? `: ${listingName}` : ''}${attempt > 1 ? ` (attempt ${attempt})` : ''}...`
          );
          // Held separately from the `withTimeout` race so a timed-out scrape
          // (which keeps running against `placePage` after it's closed below)
          // always has its eventual rejection handled — otherwise it lingers
          // as an unhandled promise holding Playwright Page/Frame/CDP-session
          // references, which adds up across a multi-hour, thousands-of
          // -listings scan.
          const scrapePromise = scrapeOnePlace(placePage, fresh[i].href, category, location, country, dateRange);
          scrapePromise.catch(() => {});
          business = await raceWithCancel(withTimeout(scrapePromise, PLACE_TIMEOUT_MS, `place ${i + 1}`), shouldStop);
        } catch (err) {
          // Google's check is not a failed listing: stop here, do not retry through it.
          if (err instanceof GoogleBlockedError) throw err;
          lastError = err;
        } finally {
          await placePage.close().catch(() => {});
        }
      }
      if (business?.name) {
        businesses.push(business);
        const access = business.reviewAccess;
        onProgress?.(
          `Collected: ${business.name} (${business.reviews.length}× 1★)` +
            (access && !access.complete ? ` [reviews NOT fully read: ${access.status}]` : '') +
            ` [${businesses.length}/${limit}]`
        );
      } else if (!shouldStop?.()) {
        skippedListings += 1;
        // Let another city's search pick it up rather than lose it for good.
        if (fresh[i].id && seenPlaceIds) seenPlaceIds.delete(fresh[i].id);
        onProgress?.(`Skipped listing ${i + 1}${listingName ? ` (${listingName})` : ''}: ${lastError?.message || 'no data'}`);
      }
    }
    // How many listings could not be read even after retrying, so the scan
    // can report them instead of presenting the city as fully covered.
    meta.skippedListings = skippedListings;
  } finally {
    for (const [key, value] of Object.entries(meta)) {
      Object.defineProperty(businesses, key, { value, enumerable: false, configurable: true });
    }
    await context.close().catch(() => {});
    if (ownsBrowser) await browser.close();
  }

  return businesses;
}

async function scrapeOnePlace(page, href, category, location, country, dateRange) {
  await page.goto(withEnglish(href, country), { waitUntil: 'domcontentloaded', timeout: 30000 });
  await throwIfBlocked(page);
  // Wait for the place's title to actually render rather than a fixed pause:
  // a heavier page (signed in) can take several seconds, and reading it too
  // early finds no name and drops the business.
  await page.waitForSelector('h1', { state: 'attached', timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(800);
  await dismissConsent(page);
  return extractBusinessFromPlacePage(page, category, location, country, dateRange);
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

/**
 * Google Maps often puts the real number on `data-item-id="phone:tel:+1…"`
 * (or the aria-label) while the button's innerText is just "Phone" — which
 * has no digits, so WhatsApp validation would skip or fail every listing.
 */
async function extractPhone(page) {
  try {
    const btn = page.locator('button[data-item-id^="phone"]').first();
    if ((await btn.count()) > 0) {
      const itemId = await btn.getAttribute('data-item-id');
      const tel = itemId?.match(/tel:([^,]*)/i);
      if (tel?.[1]) {
        const fromTel = decodeURIComponent(tel[1]).trim();
        if (fromTel.replace(/\D/g, '').length >= 8) return fromTel;
      }
      const aria = await btn.getAttribute('aria-label');
      const fromAria = aria?.match(/[\d+().\-\s]{8,}/)?.[0]?.trim();
      if (fromAria && fromAria.replace(/\D/g, '').length >= 8) return fromAria;
    }
  } catch {
    // fall through to innerText
  }
  return textOrNull(page, [
    'button[data-item-id^="phone"]',
    'button[aria-label*="Phone"]',
  ]);
}

/**
 * Reads the business's overall rating and review count from the aria-labels
 * Google puts on them ("4.5 stars", "10,976 reviews"). Exact matches only, so
 * the rating-bar rows ("5 stars, 7,658 reviews") are never mistaken for either.
 * Falls back to the looser lookups used before Google's markup changed.
 */
export async function readRatingAndReviewCount(page) {
  await page
    .waitForSelector('[aria-label*="star" i], [aria-label*="review" i]', { state: 'attached', timeout: 2500 })
    .catch(() => {});

  const exact = await page
    .evaluate(() => {
      let rating = null;
      let total = null;
      for (const el of document.querySelectorAll('[aria-label]')) {
        const label = el.getAttribute('aria-label') || '';
        if (rating === null) {
          const m = label.match(/^\s*(\d+(?:\.\d+)?)\s*stars?\s*$/i);
          if (m) rating = Number(m[1]);
        }
        if (total === null) {
          const m = label.match(/^\s*([\d,]+)\s*reviews?\s*$/i);
          if (m) total = Number(m[1].replace(/,/g, ''));
        }
        if (rating !== null && total !== null) break;
      }
      return { rating, total };
    })
    .catch(() => ({ rating: null, total: null }));

  let { rating, total: totalReviews } = exact;

  if (rating === null) {
    // Looser lookup, but never a rating-bar row: those read "5 stars, 7,658
    // reviews" (a comma), and taking the first match gave every business 5.0.
    rating = await page
      .evaluate(() => {
        for (const el of document.querySelectorAll('[aria-label*="star" i]')) {
          const label = el.getAttribute('aria-label') || '';
          if (label.includes(',')) continue;
          const m = label.match(/(\d+\.?\d*)\s*stars?/i);
          if (m) return Number(m[1]);
        }
        return null;
      })
      .catch(() => null);
  }
  if (totalReviews === null) {
    try {
      const label = await page
        .locator('span[aria-label$=" reviews"], span[aria-label$=" review"], button[aria-label$=" reviews"]')
        .first()
        .getAttribute('aria-label', { timeout: 1000 });
      const m = label?.replace(/,/g, '').match(/(\d+)\s*reviews?/i);
      if (m) totalReviews = Number(m[1]);
    } catch {
      // ignore
    }
  }
  return { rating, totalReviews };
}

async function extractBusinessFromPlacePage(page, category, location, country, dateRange) {
  const name = await textOrNull(page, ['h1.DUwDvf', 'h1']);
  if (!name) return null;

  const { rating, totalReviews } = await readRatingAndReviewCount(page);

  const address = await textOrNull(page, [
    'button[data-item-id="address"]',
    'button[aria-label*="Address"]',
  ]);
  const phone = await extractPhone(page);

  let website = null;
  try {
    website = await page
      .locator('a[data-item-id="authority"], a[aria-label*="Website"]')
      .first()
      .getAttribute('href', { timeout: 1500 });
  } catch {
    // ignore
  }

  const { reviews, access: reviewAccess } = await collectOneStarReviews(page, { totalReviews, dateRange });

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
    // How the reviews were obtained: `sorted: false` means Google did not let
    // them be sorted lowest-first, so `reviews` holds only the 1-star ones
    // among the few that were visible, not necessarily all of them.
    reviewAccess,
    source: 'google_maps',
  };
}

/**
 * One light search to learn whether Google is currently serving results:
 * 'ok', 'blocked' (its "unusual traffic" check is showing) or 'unknown'.
 * Used before a scan starts and to decide when a paused scan may continue.
 */
export async function probeGoogleMaps(browser) {
  const context = await createContext(browser);
  const page = await context.newPage();
  try {
    await page.goto(buildSearchUrl('restaurants', 'New York, NY', 'US'), { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.waitForTimeout(3000);
    try {
      await throwIfBlocked(page);
    } catch (err) {
      if (err instanceof GoogleBlockedError) return 'blocked';
    }
    return (await page.locator('[role="feed"], a[href*="/maps/place"]').count()) ? 'ok' : 'unknown';
  } catch {
    return 'unknown';
  } finally {
    await page.close().catch(() => {});
  }
}

/**
 * A business with this many 1-star reviews or fewer is read "Lowest rating"
 * first: every 1-star review sits at the top, so reading them all is quick.
 * Busier ones are read "Newest" first, back to the start of the date window.
 * Either way nothing inside the window is left unread.
 */
export const LOWEST_FIRST_MAX_ONE_STAR = 40;

const FULLY_READ = new Set(['older_than_window', 'non_one_star', 'exhausted']);

/**
 * Collects every 1-star review a business has inside `dateRange` days, and an
 * `access` record saying whether that is provably all of them.
 *
 * `access.complete` is true only when the list was sorted (verified) and then
 * read to a boundary that guarantees nothing was left below it, or when the
 * business has no 1-star reviews at all. Anything else is flagged so callers
 * never take a partial look for a complete one.
 */
export async function collectOneStarReviews(page, { totalReviews = null, dateRange = '28' } = {}) {
  const access = {
    strategy: null,
    sorted: false,
    status: SORT_STATUS.ERROR,
    detail: '',
    complete: false,
    boundary: null,
    cardsSeen: 0,
    sampleStars: [],
    sampleDates: [],
  };
  try {
    const panel = await openReviewsPanel(page);
    if (!panel.opened) {
      access.status = SORT_STATUS.REVIEWS_TAB_MISSING;
      access.detail = 'no Reviews tab found';
      return { reviews: [], access };
    }

    const oneStarCount = await readOneStarCount(page);
    if (process.env.MAPS_DEBUG) {
      const pre = await readReviewCards(page, { limit: 60 }).catch(() => []);
      const tabs = await page.evaluate(() => Array.from(document.querySelectorAll('[role=tab]')).map((t) => (t.getAttribute('aria-label') || '').slice(0, 16) + (t.getAttribute('aria-selected') === 'true' ? '*' : ''))).catch(() => []);
      console.error(`[maps-debug] before sort: opened ${JSON.stringify(panel)} | 1★ count ${oneStarCount} | visible cards ${pre.length} | tabs ${JSON.stringify(tabs)} | url ${page.url().slice(0, 70)}`);
    }
    const preferred = oneStarCount != null && oneStarCount <= LOWEST_FIRST_MAX_ONE_STAR ? 'lowest' : 'newest';
    const other = preferred === 'lowest' ? 'newest' : 'lowest';

    let order = preferred;
    let sort = await sortReviewsWithRetry(page, { order, oneStarCount });
    if (sort.status === SORT_STATUS.SORT_OPTION_MISSING || sort.status === SORT_STATUS.NOT_VERIFIED) {
      // Cannot order it that way: try the other way before giving up.
      const second = await sortReviewsWithRetry(page, { order: other, oneStarCount, attempts: 1 });
      if (second.ok) {
        order = other;
        sort = second;
      }
    }
    access.strategy = sort.ok ? order : null;
    access.sorted = sort.ok;
    access.status = sort.status;
    access.detail = sort.detail;

    if (sort.status === SORT_STATUS.NO_ONE_STAR) {
      access.complete = true;
      access.boundary = 'no_one_star_reviews';
      return { reviews: [], access };
    }

    let cards;
    if (sort.ok) {
      const loaded = await loadReviewsToBoundary(page, { order, windowDays: dateRange });
      cards = loaded.cards;
      access.boundary = loaded.boundary;
      access.complete = FULLY_READ.has(loaded.boundary);
    } else {
      // Unsorted: what is visible is all Google gave us.
      await scrollReviewPanel(page, 3);
      cards = await readReviewCards(page, { limit: 60 });
      access.complete = totalReviews != null && cards.length >= totalReviews;
    }
    access.cardsSeen = cards.length;
    access.sampleStars = (sort.sampleStars?.length ? sort.sampleStars : cards.map((c) => c.stars)).slice(0, 10);
    access.sampleDates = (sort.sampleDates?.length ? sort.sampleDates : cards.map((c) => c.date)).slice(0, 10);

    const reviews = cards
      .filter((c) => c.stars === 1)
      .map(({ reviewer, text, date, link }) => ({ stars: 1, reviewer, text, date, link }));
    return { reviews, access };
  } catch (err) {
    console.error('Error extracting reviews:', err);
    access.detail = err?.message || String(err);
    return { reviews: [], access };
  }
}

async function extractOneStarReviews(page) {
  return (await collectOneStarReviews(page)).reviews;
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

// How each page's reviews were sorted, read by scrapeBusinessSnapshot.
const recentReviewAccess = new WeakMap();

// Same card/selector logic as extractOneStarReviews, but sorted lowest-first
// and without the 1-star filter — used by the watchlist feature, which
// needs to notice ANY new review (not just qualifying 1-star ones).
async function extractRecentReviews(page, { limit = 40 } = {}) {
  const reviews = [];

  try {
    const panel = await openReviewsPanel(page);
    if (panel.opened) {
      // For the watchlist/clients scans we want the lowest-rated first so 1-stars
      // surface even when old or buried. Verified, and reported as the
      // snapshot's `reviewAccess`, never silently assumed.
      const sort = await sortLowestFirst(page, { oneStarCount: await readOneStarCount(page) });
      recentReviewAccess.set(page, { sorted: sort.ok, status: sort.status, detail: sort.detail });
      await scrollReviewPanel(page, 6);
    } else {
      recentReviewAccess.set(page, { sorted: false, status: SORT_STATUS.REVIEWS_TAB_MISSING, detail: 'no Reviews tab found' });
    }

    const raw = await page.evaluate((maxCount) => {
      const cards = Array.from(document.querySelectorAll('div.jftiEf, .G5u69c, .W_S_o'));
      const seen = new Set();
      const out = [];

      for (const root of cards) {
        // More robust star detection
        let stars = null;

        // 1. Aria-label on stars container
        const starEl = root.querySelector('[aria-label*="star" i], .kvS76c, span[role="img"]');
        const aria = starEl?.getAttribute('aria-label') || '';
        const starMatch = aria.match(/(\d+)\s*stars?/i);
        if (starMatch) {
          stars = Number(starMatch[1]);
        } else {
          // 2. Count visual "filled" stars
          const filled = root.querySelectorAll('.vzX5Ic, .GDS5cc img[src*="star_filled"]').length;
          if (filled > 0) {
            stars = filled;
          } else {
            // 3. Check for specific 1-star classes/icons
            if (root.querySelector('.L80Sge, .xS9p9e')) { // Example 1-star indicator classes
               stars = 1;
            }
          }
        }

        const reviewer = root.querySelector('.d4r55, .TSZ61d')?.textContent?.trim() || 'Anonymous';
        const date = root.querySelector('.rsqaWe, .DU9u7b')?.textContent?.trim() || 'Unknown';
        const text = root.querySelector('.wiI7hc, .MyEned')?.textContent?.trim() || '';

        // Try to find a direct link to the review
        let link = null;
        const reviewId = root.getAttribute('data-review-id');
        if (reviewId) {
          link = `https://www.google.com/maps/reviews/data=!4m3!8m2!3m1!1s${reviewId}?hl=en`;
        } else {
          const menuBtn = root.querySelector('button[aria-label*="menu" i]');
          const id = menuBtn?.getAttribute('data-review-id');
          if (id) link = `https://www.google.com/maps/reviews/data=!4m3!8m2!3m1!1s${id}?hl=en`;
        }

        // Relative date strings ("2 months ago") drift as time passes, so the
        // dedup/diff key deliberately excludes date — reviewer+text is what
        // actually identifies the same review across repeated scans.
        const key = `${reviewer}|${text.slice(0, 80)}`;
        if (seen.has(key)) continue;
        seen.add(key);

        out.push({ stars, reviewer, text, date, link });
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
export async function scrapeBusinessSnapshot(mapsUrl, country, { dateRange } = {}) {
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

    const { rating, totalReviews } = await readRatingAndReviewCount(page);

    // With a `dateRange` the caller wants every 1-star review inside it (the
    // clients / sales scans): read them completely, exactly as the main scan
    // does. Without one (the watchlist) it is the lowest-rated few, as before.
    let reviews;
    let reviewAccess;
    if (dateRange) {
      const collected = await collectOneStarReviews(page, { totalReviews, dateRange });
      reviews = collected.reviews;
      reviewAccess = collected.access;
    } else {
      reviews = await extractRecentReviews(page, { limit: 10 });
      reviewAccess = recentReviewAccess.get(page);
    }

    return {
      name,
      mapsUrl: withEnglish(page.url(), country),
      rating,
      totalReviews,
      reviews,
      // Whether the reviews were verifiably sorted lowest-first; when not,
      // an empty `reviews` must not be read as "no 1-star reviews".
      reviewAccess: reviewAccess || { sorted: false, status: SORT_STATUS.ERROR, complete: false, detail: 'not attempted' },
    };
  } finally {
    await browser.close();
  }
}
