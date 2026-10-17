import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from 'playwright';
import { searchBusinesses, placeIdFromHref, cannotHaveOneStar } from './googleMapsScraper.js';
import { GoogleBlockedError } from './googleBlock.js';
import { placeHtml } from './mapsFixture.js';

let browser = null;
let launchError = null;
before(async () => {
  try {
    browser = await chromium.launch({ headless: true });
  } catch (err) {
    launchError = (err?.message || String(err)).split('\n')[0];
  }
});
after(async () => browser?.close());

const noPace = { acquire: async () => {} };
const href = (name, a, b) => `https://www.google.com/maps/place/${encodeURIComponent(name)}/data=!4m7!3m6!1s${a}:${b}!8m2!3d1!4d2`;
const LISTINGS = [
  { name: 'Alpha Auto', a: '0x8644b1', b: '0xaaa111' },
  { name: 'Bravo Auto', a: '0x8644b2', b: '0xbbb222' },
  { name: 'Charlie Auto', a: '0x8644b3', b: '0xccc333' },
];
const feedHtml = (items) =>
  `<html><body><div role="feed">${items.map((l) => `<a href="${href(l.name, l.a, l.b)}" aria-label="${l.name}">${l.name}</a>`).join('')}</div></body></html>`;

/** A "browser" whose contexts have Google replaced by local pages. */
function fakeGoogle({ search, place, requests = [] }) {
  return {
    newContext: async (options) => {
      const context = await browser.newContext(options);
      await context.route(/^https:\/\/www\.google\.com\/maps\/search\//, (route) => {
        requests.push('search');
        return route.fulfill({ status: 200, contentType: 'text/html', body: search });
      });
      await context.route(/^https:\/\/www\.google\.com\/maps\/place\//, (route) => {
        requests.push('place');
        return place === 'abort'
          ? route.abort()
          : route.fulfill({ status: 200, contentType: 'text/html', body: place ?? placeHtml({ sort: 'works' }) });
      });
      return context;
    },
    close: async () => {},
  };
}

const run = (t, name, fn) =>
  test(name, async (tc) => {
    if (!browser) return tc.skip(`Chromium unavailable: ${launchError}`);
    await fn(tc);
  });

test('the place id is read from a listing link, and is the same whichever city listed it', () => {
  const a = placeIdFromHref(href('X', '0x865b32b0b31cd661', '0xa856338abc'));
  assert.equal(a, '0x865b32b0b31cd661:0xa856338abc');
  assert.equal(placeIdFromHref(`https://www.google.com/maps/place/X/@30.1,-97.7,17z/data=!4m7!3m6!1s0x865b32b0b31cd661:0xa856338abc!8m2`), a);
  assert.equal(placeIdFromHref('https://www.google.com/maps/place/NoId'), null);
});

run(null, 'a business already read for another city is not read again, and the others are claimed', async () => {
  const seen = new Set(['0x8644b1:0xaaa111']); // Alpha was read for the previous city
  const requests = [];
  const found = await searchBusinesses('auto', 'Hoover, Alabama', {
    maxResults: 5,
    browser: fakeGoogle({ search: feedHtml(LISTINGS), requests }),
    seenPlaceIds: seen,
    pace: noPace,
    dateRange: '28',
  });
  assert.equal(found.listingsFound, 3);
  assert.equal(found.duplicatesSkipped, 1);
  assert.equal(found.length, 2, 'Bravo and Charlie');
  assert.equal(requests.filter((r) => r === 'place').length, 2, 'only two place pages were opened');
  assert.ok(seen.has('0x8644b2:0xbbb222') && seen.has('0x8644b3:0xccc333'), 'now claimed');
  assert.equal(found.searchStatus, 'ok');
});

run(null, 'Google\'s unusual-traffic page on the search is a block, not an empty city', async () => {
  const blocked = '<html><body>About this page. Our systems have detected unusual traffic from your computer network. This page checks to see if it is really you sending the requests, and not a robot.</body></html>';
  await assert.rejects(
    () => searchBusinesses('auto', 'Hoover, Alabama', { browser: fakeGoogle({ search: blocked }), pace: noPace, feedTimeoutMs: 800 }),
    (err) => err instanceof GoogleBlockedError && err.code === 'GOOGLE_BLOCKED',
  );
});

run(null, 'a block on a place page stops the search at once: no retry through it, nothing counted as skipped', async () => {
  const blocked = '<html><body>Our systems have detected unusual traffic from your computer network.</body></html>';
  const requests = [];
  await assert.rejects(
    () => searchBusinesses('auto', 'Hoover, Alabama', {
      maxResults: 5,
      browser: fakeGoogle({ search: feedHtml(LISTINGS), place: blocked, requests }),
      pace: noPace,
    }),
    (err) => err instanceof GoogleBlockedError,
  );
  assert.equal(requests.filter((r) => r === 'place').length, 1, 'one place page, then it stopped');
});

run(null, 'Google saying it found nothing is "no_results", whether or not a result list is drawn', async () => {
  const withFeed = await searchBusinesses('auto', 'Nowhere, Alaska', {
    browser: fakeGoogle({ search: '<html><body><div role="feed">Google Maps can\'t find auto in Nowhere</div></body></html>' }),
    pace: noPace,
    feedTimeoutMs: 1500,
  });
  assert.equal(withFeed.length, 0);
  assert.equal(withFeed.searchStatus, 'no_results');

  const noFeed = await searchBusinesses('auto', 'Nowhere, Alaska', {
    browser: fakeGoogle({ search: '<html><body><p>Google Maps can\'t find auto in Nowhere</p></body></html>' }),
    pace: noPace,
    feedTimeoutMs: 800,
  });
  assert.equal(noFeed.searchStatus, 'no_results');
});

run(null, 'no result list at all is "feed_missing": a failure, not an empty city', async () => {
  const found = await searchBusinesses('auto', 'Anchorage, Alaska', {
    browser: fakeGoogle({ search: '<html><body><p>Something else entirely</p></body></html>' }),
    pace: noPace,
    feedTimeoutMs: 800,
  });
  assert.equal(found.length, 0);
  assert.equal(found.searchStatus, 'feed_missing');
});

run(null, 'a listing that cannot be opened is skipped after its retry and handed back for another city to pick up', async () => {
  const seen = new Set();
  const requests = [];
  const found = await searchBusinesses('auto', 'Hoover, Alabama', {
    maxResults: 2,
    browser: fakeGoogle({ search: feedHtml(LISTINGS.slice(0, 1)), place: 'abort', requests }),
    seenPlaceIds: seen,
    pace: noPace,
  });
  assert.equal(found.length, 0);
  assert.equal(found.skippedListings, 1);
  assert.equal(requests.filter((r) => r === 'place').length, 2, 'tried twice');
  assert.equal(seen.size, 0, 'released, so a neighbouring city\'s search may still read it');
});

// ---- results that provably hold no 1-star review are not opened ---------------------------

test('a business is skipped only when its rating and review count make a 1-star review impossible', () => {
  // One 1-star among n reviews costs at least 4/n of average; a displayed rating r is true to within 0.05.
  assert.equal(cannotHaveOneStar(5.0, 40), true, '40 reviews all at 5.0: no room for a 1-star');
  assert.equal(cannotHaveOneStar(5.0, 79), true);
  assert.equal(cannotHaveOneStar(5.0, 80), false, '80 reviews could hide one 1-star at 4.95');
  assert.equal(cannotHaveOneStar(4.9, 26), true);
  assert.equal(cannotHaveOneStar(4.9, 27), false);
  assert.equal(cannotHaveOneStar(4.5, 7), true);
  assert.equal(cannotHaveOneStar(4.5, 8), false);
  assert.equal(cannotHaveOneStar(3.0, 2), false, 'a low-rated business is never skipped');
  assert.equal(cannotHaveOneStar(4.8, 0), true, 'no reviews at all');
});

test('unknown facts never skip a business', () => {
  assert.equal(cannotHaveOneStar(null, 10), false);
  assert.equal(cannotHaveOneStar(4.9, null), false);
  assert.equal(cannotHaveOneStar(NaN, NaN), false);
  assert.equal(cannotHaveOneStar(undefined, undefined), false);
});

test('the rule is exact: no business it skips could have held a 1-star review', () => {
  // Brute force: for every (n, k>=1) the best possible average with k one-star reviews, rounded to 0.1, is a
  // rating the rule must NOT skip.
  for (let n = 1; n <= 400; n++) {
    for (const k of [1, 2, 3]) {
      if (k > n) continue;
      const bestAvg = (5 * (n - k) + k) / n;
      const shown = Math.round(bestAvg * 10) / 10;
      assert.equal(cannotHaveOneStar(shown, n), false, `n=${n} k=${k} shown=${shown}`);
    }
  }
});

const cardFeed = (items) =>
  `<html><body><div role="feed">${items
    .map((l) => `<div role="article"><a href="${href(l.name, l.a, l.b)}" aria-label="${l.name}">${l.name}</a>${l.facts ? `<span role="img" aria-label="${l.facts}"></span>` : ''}</div>`)
    .join('')}</div></body></html>`;

run(null, 'result cards that prove "no 1-star possible" are not opened; the rest are', async () => {
  const requests = [];
  const found = await searchBusinesses('auto', 'Hoover, Alabama', {
    maxResults: 5,
    browser: fakeGoogle({
      search: cardFeed([
        { ...LISTINGS[0], facts: '5.0 stars 12 Reviews' }, // provably none: skipped
        { ...LISTINGS[1], facts: '4.2 stars 1,200 Reviews' }, // read
        { ...LISTINGS[2] }, // no facts on the card: read
      ]),
      requests,
    }),
    pace: noPace,
  });
  assert.equal(found.listingsFound, 3);
  assert.equal(found.prefiltered, 1);
  assert.equal(found.length, 2);
  assert.equal(requests.filter((r) => r === 'place').length, 2);
});

run(null, 'a grid point is searched around its coordinates, not by place name', async () => {
  let url = '';
  const google = fakeGoogle({ search: cardFeed([]) });
  const original = google.newContext;
  google.newContext = async (o) => {
    const c = await original(o);
    c.on('request', (r) => { if (/maps\/search/.test(r.url())) url = r.url(); });
    return c;
  };
  await searchBusinesses('auto repair', 'Houston, Texas', {
    browser: google,
    pace: noPace,
    center: { lat: 29.6118, lng: -95.489, zoom: 14 },
    feedTimeoutMs: 600,
  });
  assert.match(url, /\/maps\/search\/auto%20repair\/@29\.6118,-95\.489,14z/);
  assert.doesNotMatch(url, /Houston/);
});
