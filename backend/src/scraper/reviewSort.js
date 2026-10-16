/**
 * Opening a Google Maps place's reviews and sorting them "Lowest rating", with
 * proof that the sort happened.
 *
 * Google shows anonymous visitors only a handful of reviews and answers a
 * click on "Sort" with a "Sign in to get the best of Google Maps" prompt. This
 * module never works around that: it detects the prompt, closes it like any
 * visitor would, and reports that the reviews are NOT sorted, so callers never
 * mistake the few unsorted reviews for every 1-star review.
 *
 * Every function takes a Playwright `page`, so the tests drive it against
 * local HTML fixtures instead of the live site.
 */

import { parseRelativeDate, isWithinRange } from '../lib/dateUtils.js';

export const SORT_STATUS = Object.freeze({
  OK: 'ok',
  // The business has no 1-star reviews at all (read from its rating bars), so
  // there was nothing to sort for and no sign-in prompt was risked.
  NO_ONE_STAR: 'no_one_star_reviews',
  SIGN_IN_REQUIRED: 'signin_required',
  REVIEWS_TAB_MISSING: 'reviews_tab_missing',
  SORT_CONTROL_MISSING: 'sort_control_missing',
  SORT_OPTION_MISSING: 'sort_option_missing',
  NOT_VERIFIED: 'sort_not_verified',
  ERROR: 'error',
});

const SORTED = new Set([SORT_STATUS.OK, SORT_STATUS.NO_ONE_STAR]);

/** Whether a status means the reviews that follow can be trusted as complete. */
export function isSortSuccess(status) {
  return SORTED.has(status);
}

// ---------------------------------------------------------------------------
// Diagnostics: one counter per outcome for the life of the process, so a scan
// can say "4,812 of 13,563 businesses could not be sorted (sign-in required)".
// ---------------------------------------------------------------------------

const counters = new Map();
let sessionMode = false;
let warnedSignIn = false;

export function setSessionMode(active) {
  sessionMode = Boolean(active);
}

export function resetSortDiagnostics() {
  counters.clear();
  warnedSignIn = false;
}

export function recordSort(status) {
  counters.set(status, (counters.get(status) || 0) + 1);
}

export function getSortDiagnostics() {
  const out = {};
  for (const [k, v] of counters) out[k] = v;
  return out;
}

/** One line for the scan log, or null when nothing went wrong. */
export function describeSortDiagnostics() {
  const total = [...counters.values()].reduce((a, b) => a + b, 0);
  if (!total) return null;
  const bad = [...counters.entries()].filter(([k]) => !SORTED.has(k));
  if (!bad.length) return `Review sorting: all ${total} lookups sorted lowest-rating-first.`;
  const parts = bad.map(([k, v]) => `${v} ${k}`).join(', ');
  const hint = counters.get(SORT_STATUS.SIGN_IN_REQUIRED)
    ? sessionMode
      ? ' The saved Google session is not signed in or has expired: sign in again (Excel Scan page, or `npm run maps:login`).'
      : ' Google asks anonymous visitors to sign in to sort reviews: use "Sign in to Google" on the Excel Scan page, or `npm run maps:login`.'
    : '';
  return `Review sorting: ${total - bad.reduce((n, [, v]) => n + v, 0)}/${total} sorted; not sorted: ${parts}.${hint}`;
}

function warnSignInOnce() {
  if (warnedSignIn) return;
  warnedSignIn = true;
  console.warn(
    sessionMode
      ? '[maps] Google asked to sign in although a saved session is in use: the session is signed out or has expired. Run `npm run maps:login`. Reviews will not be sorted until then.'
      : '[maps] Google asked to sign in before sorting reviews. Reviews are NOT sorted, so 1-star reviews will be missed. Sign in to Google (Excel Scan page > "Sign in to Google", or `npm run maps:login`).',
  );
}

// ---------------------------------------------------------------------------
// Pure verification
// ---------------------------------------------------------------------------

/**
 * Decides from the stars of the reviews now on screen (in order) whether the
 * list really is lowest-rating-first.
 *
 * @param {number[]} stars       stars of the visible reviews, top to bottom
 * @param {number|null} oneStarCount  how many 1-star reviews the business has
 *   (from its rating bars), or null if unknown
 */
export function verifyLowestFirst(stars, oneStarCount = null) {
  const list = (stars || []).filter((n) => Number.isFinite(n));
  if (!list.length) return { verified: false, reason: 'no_reviews_visible' };
  for (let i = 1; i < list.length; i++) {
    if (list[i] < list[i - 1]) return { verified: false, reason: 'not_ascending' };
  }
  if (oneStarCount != null && oneStarCount > 0) {
    // A lowest-first list opens with the 1-star reviews.
    return list[0] === 1 ? { verified: true } : { verified: false, reason: 'first_review_not_one_star' };
  }
  if (list[0] <= 2) return { verified: true };
  // Ascending but starting high: only convincing when the ratings actually
  // rise; a run of identical high ratings looks exactly like an unsorted list.
  return new Set(list).size > 1 ? { verified: true } : { verified: false, reason: 'cannot_confirm_order' };
}

/**
 * Whether the dates of the reviews now on screen (top to bottom, as Google's
 * relative text: "2 weeks ago") run newest to oldest.
 */
export function verifyNewestFirst(dates, now = new Date()) {
  const times = (dates || []).map((d) => parseRelativeDate(d, now)).filter(Boolean).map((d) => d.getTime());
  if (!times.length) return { verified: false, reason: 'no_dates_visible' };
  for (let i = 1; i < times.length; i++) {
    if (times[i] > times[i - 1]) return { verified: false, reason: 'not_newest_first' };
  }
  return { verified: true };
}

// ---------------------------------------------------------------------------
// Page interaction
// ---------------------------------------------------------------------------

const CARD_SELECTOR = '[data-review-id], div.jftiEf, .G5u69c, .W_S_o';

/** True when Google is showing its sign-in prompt over the place page. */
export async function detectSignInPrompt(page) {
  try {
    if (/accounts\.google\.com/i.test(page.url())) return true;
    const text = page.getByText(/sign[\s-]*in to get the best of google maps/i).first();
    if (await text.isVisible({ timeout: 300 }).catch(() => false)) return true;
    const dialog = page.getByRole('dialog').filter({ hasText: /sign[\s-]*in/i }).first();
    return await dialog.isVisible({ timeout: 300 }).catch(() => false);
  } catch {
    return false;
  }
}

/** Closes the prompt the way any visitor would; never signs in. */
export async function dismissSignInPrompt(page) {
  try {
    if (/accounts\.google\.com/i.test(page.url())) {
      await page.goBack({ timeout: 8000 }).catch(() => {});
      return;
    }
    const dismiss = page.getByRole('button', { name: /^(dismiss|no thanks|not now|close)$/i }).first();
    if (await dismiss.isVisible({ timeout: 300 }).catch(() => false)) {
      await dismiss.click({ timeout: 2000 }).catch(() => {});
    } else {
      await page.keyboard.press('Escape').catch(() => {});
    }
    await page.waitForTimeout(300);
  } catch {
    // best effort
  }
}

/**
 * Reads the review cards now on screen, in order. Looks for the top-level
 * element carrying `data-review-id` first (stable across Google's class-name
 * changes) and falls back to the older class names.
 */
export async function readReviewCards(page, { limit = 60 } = {}) {
  return page.evaluate(({ sel, max }) => {
    const all = Array.from(document.querySelectorAll(sel));
    // Top-level cards only: a card contains several nested data-review-id nodes.
    const roots = all.filter((el) => !el.parentElement?.closest(sel));
    const seen = new Set();
    const out = [];
    for (const root of roots) {
      let stars = null;
      for (const el of root.querySelectorAll('[aria-label]')) {
        const label = el.getAttribute('aria-label') || '';
        const m = label.match(/(\d+(?:\.\d+)?)\s*stars?\b/i) || label.match(/rated\s+(\d+(?:\.\d+)?)\s+out of/i);
        if (m) {
          stars = Math.round(Number(m[1]));
          break;
        }
      }
      if (stars === null) {
        const filled = root.querySelectorAll('.vzX5Ic').length;
        if (filled > 0) stars = filled;
      }

      const reviewer = root.querySelector('.d4r55, .TSZ61d')?.textContent?.trim() || 'Anonymous';
      let date = root.querySelector('.rsqaWe, .DU9u7b')?.textContent?.trim() || '';
      if (!date) {
        // Class names drift; the date is the text that reads "<n> <unit> ago".
        const leaf = Array.from(root.querySelectorAll('span, div')).find(
          (e) => e.children.length === 0 && /\b(ago|just now)\b|^\d{4}$/i.test((e.textContent || '').trim()),
        );
        date = leaf?.textContent?.trim() || 'Unknown';
      }
      const text = root.querySelector('.wiI7hc, .MyEned')?.textContent?.trim() || '';

      let link = null;
      const id = root.getAttribute('data-review-id') || root.querySelector('[data-review-id]')?.getAttribute('data-review-id');
      if (id) link = `https://www.google.com/maps/reviews/data=!4m3!8m2!3m1!1s${id}?hl=en`;

      const key = `${reviewer}|${date}|${text.slice(0, 50)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ stars, reviewer, text, date, link });
      if (out.length >= max) break;
    }
    return out;
  }, { sel: CARD_SELECTOR, max: limit });
}

/** How many 1-star reviews the business has, from its rating bars; null if not shown. */
export async function readOneStarCount(page) {
  try {
    return await page.evaluate(() => {
      for (const el of document.querySelectorAll('[aria-label]')) {
        const m = (el.getAttribute('aria-label') || '').match(/^\s*1\s*stars?\s*,\s*([\d,]+)\s*reviews?/i);
        if (m) return Number(m[1].replace(/,/g, ''));
      }
      return null;
    });
  } catch {
    return null;
  }
}

/** Clicks the place's "Reviews" tab (unless its reviews are already showing). */
export async function openReviewsPanel(page) {
  try {
    if (await page.locator(CARD_SELECTOR).count()) return { opened: true };

    let tab = page.getByRole('tab', { name: /reviews/i }).first();
    if (!(await tab.count())) {
      tab = page.locator('button[role="tab"], .hh706e button').filter({ hasText: /reviews/i }).first();
    }
    if (!(await tab.count())) return { opened: false };

    await tab.click({ timeout: 4000 });
    await page.waitForSelector(CARD_SELECTOR, { state: 'attached', timeout: 5000 }).catch(() => {});
    return { opened: true };
  } catch {
    return { opened: false };
  }
}

/**
 * Scrolls the reviews list itself. A wheel event goes to whatever is under the
 * pointer, which is often the map, so find the scrollable ancestor of the
 * first card and scroll that.
 */
export async function scrollReviewPanel(page, times = 3) {
  for (let i = 0; i < times; i++) {
    const scrolled = await page
      .evaluate((sel) => {
        let el = document.querySelector(sel);
        while (el && el !== document.body) {
          const oy = getComputedStyle(el).overflowY;
          if ((oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight) {
            el.scrollTop = el.scrollHeight;
            return true;
          }
          el = el.parentElement;
        }
        return false;
      }, CARD_SELECTOR)
      .catch(() => false);
    if (!scrolled) await page.mouse.wheel(0, 2000).catch(() => {});
    await page.waitForTimeout(600);
  }
}

function sortControl(page) {
  return page
    .getByRole('button', { name: /\bsort\b/i })
    .or(page.locator('button[aria-label*="Sort" i], button.g67oK'))
    .first();
}

const OPTION_NAME = { lowest: /lowest/i, newest: /newest/i };

function sortOption(page, order) {
  const name = OPTION_NAME[order];
  return page
    .getByRole('menuitemradio', { name })
    .or(page.getByRole('menuitem', { name }))
    .or(page.locator('[role="menuitemradio"], [role="menuitem"], [role="option"], .fx07Cc').filter({ hasText: name }))
    .first();
}

/**
 * Sorts the open reviews list ("lowest" rating first, or "newest" first) and
 * verifies it.
 *
 * Returns `{ ok, status, detail, sampleStars, sampleDates }`. `ok` is true
 * only when the list was verified in that order, or when there was nothing to
 * sort for. Anything else (sign-in prompt, no sort control, option missing,
 * order not as expected) is a failure the caller must not treat as a full set
 * of reviews.
 */
export async function sortReviews(page, { order = 'lowest', oneStarCount = null, now = new Date() } = {}) {
  const done = (status, detail, cards = []) => {
    recordSort(status);
    if (status === SORT_STATUS.SIGN_IN_REQUIRED) warnSignInOnce();
    return {
      ok: isSortSuccess(status),
      status,
      detail,
      sampleStars: cards.map((c) => c.stars),
      sampleDates: cards.map((c) => c.date),
    };
  };

  try {
    if (oneStarCount === 0) {
      return done(SORT_STATUS.NO_ONE_STAR, 'rating bars show 0 one-star reviews; nothing to sort for');
    }

    if (await detectSignInPrompt(page)) {
      await dismissSignInPrompt(page);
      return done(SORT_STATUS.SIGN_IN_REQUIRED, 'sign-in prompt already showing');
    }

    const sortBtn = sortControl(page);
    if (!(await sortBtn.count())) {
      return done(SORT_STATUS.SORT_CONTROL_MISSING, 'no Sort control on the reviews panel');
    }
    await sortBtn.click({ timeout: 4000 });
    await page.waitForTimeout(700);

    if (await detectSignInPrompt(page)) {
      await dismissSignInPrompt(page);
      return done(SORT_STATUS.SIGN_IN_REQUIRED, 'Google asked to sign in when Sort was clicked');
    }

    const option = sortOption(page, order);
    try {
      await option.waitFor({ state: 'visible', timeout: 2500 });
    } catch {
      await page.keyboard.press('Escape').catch(() => {});
      return done(SORT_STATUS.SORT_OPTION_MISSING, `Sort menu did not offer "${order === 'newest' ? 'Newest' : 'Lowest rating'}"`);
    }
    await option.click({ timeout: 3000 });

    // Give the list time to reorder, then prove it did.
    await page.waitForTimeout(1500);
    if (await detectSignInPrompt(page)) {
      await dismissSignInPrompt(page);
      return done(SORT_STATUS.SIGN_IN_REQUIRED, 'Google asked to sign in after choosing a sort order');
    }
    const cards = await readReviewCards(page, { limit: 12 });
    const check =
      order === 'newest'
        ? verifyNewestFirst(cards.map((c) => c.date), now)
        : verifyLowestFirst(cards.map((c) => c.stars), oneStarCount);
    return check.verified
      ? done(SORT_STATUS.OK, `verified ${order === 'newest' ? 'newest' : 'lowest-rating'}-first`, cards)
      : done(SORT_STATUS.NOT_VERIFIED, `order not confirmed (${check.reason})`, cards);
  } catch (err) {
    return done(SORT_STATUS.ERROR, err?.message || String(err));
  }
}

/** Kept for callers that only want the lowest-rating-first sort. */
export function sortLowestFirst(page, opts = {}) {
  return sortReviews(page, { ...opts, order: 'lowest' });
}

const RETRYABLE = new Set([
  SORT_STATUS.SORT_CONTROL_MISSING,
  SORT_STATUS.SORT_OPTION_MISSING,
  SORT_STATUS.NOT_VERIFIED,
  SORT_STATUS.ERROR,
]);

/**
 * `sortReviews`, tried again when the failure may just be timing (the menu not
 * yet rendered, the list not yet reordered). A sign-in prompt is final: trying
 * again cannot help, and is how an expired session is recognised.
 */
export async function sortReviewsWithRetry(page, { attempts = 2, ...opts } = {}) {
  let result;
  for (let i = 0; i < attempts; i++) {
    result = await sortReviews(page, opts);
    if (result.ok || !RETRYABLE.has(result.status)) return result;
    await page.keyboard.press('Escape').catch(() => {});
    await page.waitForTimeout(1000);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Reading every review that matters
// ---------------------------------------------------------------------------

/** Most review cards read for one business: a runaway guard, not a target. */
export const MAX_CARDS = 800;

/**
 * Scrolls the (already sorted) review list until nothing that matters can be
 * further down, reading as it goes.
 *
 *  - `lowest`: stops once a review rated above 1 star appears (every 1-star
 *    review is above it).
 *  - `newest`: stops once a review older than `windowDays` appears (every
 *    review inside the window is above it).
 *
 * `boundary` says why it stopped; only `older_than_window`, `non_one_star` and
 * `exhausted` mean nothing was left unread. `capped` and `timeout` do not.
 */
export async function loadReviewsToBoundary(page, { order, windowDays, maxCards = MAX_CARDS, maxMs = 90000, now = new Date() }) {
  const started = Date.now();
  let cards = await readReviewCards(page, { limit: maxCards });
  let stalls = 0;
  let scrolls = 0;

  const reached = () => {
    if (order === 'lowest') return cards.some((c) => c.stars != null && c.stars > 1) ? 'non_one_star' : null;
    for (const c of cards) {
      const parsed = parseRelativeDate(c.date, now);
      if (parsed && !isWithinRange(c.date, windowDays, now)) return 'older_than_window';
    }
    return null;
  };

  for (;;) {
    const boundary = reached();
    if (boundary) return { cards, boundary, scrolls };
    if (cards.length >= maxCards) return { cards, boundary: 'capped', scrolls };
    if (Date.now() - started > maxMs) return { cards, boundary: 'timeout', scrolls };
    if (stalls >= 3) return { cards, boundary: 'exhausted', scrolls };

    const before = cards.length;
    await scrollReviewPanel(page, 1);
    scrolls += 1;
    cards = await readReviewCards(page, { limit: maxCards });
    stalls = cards.length > before ? 0 : stalls + 1;
  }
}
