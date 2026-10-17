import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isBlockedPage, throwIfBlocked, GoogleBlockedError } from './googleBlock.js';
import { PaceLimiter, perMinuteFromEnv } from './rateLimit.js';
import { useChromium } from './domTestHarness.js';

const domTest = useChromium();

test('Google\'s unusual-traffic page is recognised by URL or by its text', () => {
  assert.equal(isBlockedPage({ url: 'https://www.google.com/sorry/index?continue=https://www.google.com/maps/search/x' }), true);
  assert.equal(isBlockedPage({ url: 'https://www.google.co.uk/sorry/index' }), true);
  assert.equal(isBlockedPage({ url: 'https://www.google.com/maps', text: 'Our systems have detected unusual traffic from your computer network.' }), true);
  assert.equal(isBlockedPage({ text: 'This page checks to see if it\'s really you sending the requests, and not a robot.' }), true);
});

test('ordinary Maps pages are not mistaken for a block', () => {
  assert.equal(isBlockedPage({ url: 'https://www.google.com/maps/search/cafe', text: 'Results  Rating  Hours  All filters  Saved  Recents' }), false);
  assert.equal(isBlockedPage({}), false);
  // The phrase appearing deep in a long review must not count.
  assert.equal(isBlockedPage({ url: 'https://www.google.com/maps/place/x', text: 'a'.repeat(3000) + ' unusual traffic' }), false);
});

domTest('a page showing the check raises GoogleBlockedError; a normal page does not', async (page) => {
  await page.route('https://www.google.com/sorry/**', (route) =>
    route.fulfill({ status: 200, contentType: 'text/html', body: '<html><body>About this page. Our systems have detected unusual traffic from your computer network.</body></html>' }));
  await page.route('https://www.google.com/maps/**', (route) =>
    route.fulfill({ status: 200, contentType: 'text/html', body: '<html><body><div role="feed">Results</div></body></html>' }));

  await page.goto('https://www.google.com/maps/search/cafe');
  await throwIfBlocked(page); // fine

  await page.goto('https://www.google.com/sorry/index?continue=x');
  await assert.rejects(() => throwIfBlocked(page), (err) => {
    assert.ok(err instanceof GoogleBlockedError);
    assert.equal(err.code, 'GOOGLE_BLOCKED');
    assert.match(err.message, /unusual traffic/);
    return true;
  });
});

// ---- the pace ---------------------------------------------------------------

test('callers are spaced to stay under the per-minute budget, however many ask at once', async () => {
  const waits = [];
  // A frozen clock: everyone asks at the same instant, so each wait is how long that caller is queued.
  const pace = new PaceLimiter(30, { now: () => 1000, sleep: async (ms) => { waits.push(ms); }, jitter: 0 }); // 30/min = 2s apart
  await Promise.all([pace.acquire(), pace.acquire(), pace.acquire(), pace.acquire()]);
  assert.deepEqual(waits, [2000, 4000, 6000], 'the first goes at once, the rest queue 2s apart');
});

test('an idle limiter lets the next caller straight through', async () => {
  let now = 0;
  const waits = [];
  const pace = new PaceLimiter(60, { now: () => now, sleep: async (ms) => { waits.push(ms); now += ms; }, jitter: 0 });
  await pace.acquire();
  now += 60000; // a long quiet spell
  await pace.acquire();
  assert.deepEqual(waits, []);
});

test('jitter only ever lengthens the gap, never shortens it below the budget', async () => {
  let now = 0;
  const waits = [];
  const pace = new PaceLimiter(60, { now: () => now, sleep: async (ms) => { waits.push(ms); now += ms; }, jitter: 0.5 });
  for (let i = 0; i < 20; i++) await pace.acquire();
  assert.ok(waits.every((w) => w >= 1000 - 1e-6), 'never faster than 60/min');
});

test('the budget can be set from MAPS_MAX_PLACES_PER_MINUTE, with a sane default and ceiling', () => {
  assert.equal(perMinuteFromEnv({}), 20);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: '12' }), 12);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: 'abc' }), 20);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: '99999' }), 120);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: '-3' }), 20);
});

// ---- the pace that finds its own level --------------------------------------------

import { AdaptivePace } from './rateLimit.js';

function adaptive(opts = {}) {
  let now = 0;
  const pace = new AdaptivePace({ start: 10, min: 4, max: 16, stepEveryMs: 60000, step: 2, now: () => now, sleep: async () => {}, jitter: 0, ...opts });
  return { pace, advance: (ms) => { now += ms; } };
}

test('it speeds up gradually while healthy, never past the ceiling', () => {
  const { pace, advance } = adaptive();
  assert.equal(pace.perMinute, 10);
  pace.noteHealthy(); // too soon
  assert.equal(pace.perMinute, 10);
  for (let i = 0; i < 10; i++) { advance(61000); pace.noteHealthy(); }
  assert.equal(pace.perMinute, 16, 'stops at the ceiling');
});

test('a block halves the rate, down to a floor, and the climb back is slow', () => {
  const { pace, advance } = adaptive({ start: 16 });
  pace.noteBlocked();
  assert.equal(pace.perMinute, 8);
  pace.noteBlocked();
  assert.equal(pace.perMinute, 4);
  pace.noteBlocked();
  assert.equal(pace.perMinute, 4, 'never below the floor');
  advance(30000); pace.noteHealthy();
  assert.equal(pace.perMinute, 4, 'a block resets the healthy timer');
  advance(61000); pace.noteHealthy();
  assert.equal(pace.perMinute, 6);
});

test('the spacing between pages follows the current rate', async () => {
  const waits = [];
  const pace = new AdaptivePace({ start: 30, min: 4, max: 30, now: () => 1000, sleep: async (ms) => { waits.push(ms); }, jitter: 0 });
  await Promise.all([pace.acquire(), pace.acquire()]);
  assert.deepEqual(waits, [2000]);
  pace.noteBlocked(); // 15/min = 4s apart
  waits.length = 0;
  pace.next = 0;
  await Promise.all([pace.acquire(), pace.acquire()]);
  assert.deepEqual(waits, [4000]);
});
