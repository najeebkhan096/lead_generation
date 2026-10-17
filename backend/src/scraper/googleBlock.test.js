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
  assert.equal(perMinuteFromEnv({}), 40);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: '12' }), 12);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: 'abc' }), 40);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: '99999' }), 120);
  assert.equal(perMinuteFromEnv({ MAPS_MAX_PLACES_PER_MINUTE: '-3' }), 40);
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

// ---- early brake and memory ---------------------------------------------------------------

function memoryStore(initial = {}) {
  let data = { ...initial };
  return { load: () => data, save: (o) => { data = o; }, get: () => data };
}

test('early brake: when pages start failing, the pace is cut by a quarter before any block', () => {
  const { pace } = adaptive({ start: 16, max: 16 });
  assert.equal(pace.noteOutcome(40, 0), false, 'healthy');
  assert.equal(pace.noteOutcome(10, 1), false, 'a stray failure is not a trend');
  assert.equal(pace.perMinute, 16);
  assert.equal(pace.noteOutcome(10, 6), true, 'a run of failures trips the brake');
  assert.equal(pace.perMinute, 12);
});

test('the brake judges fresh evidence after it fires, and needs enough reads to judge at all', () => {
  const { pace } = adaptive({ start: 16, max: 16 });
  assert.equal(pace.noteOutcome(2, 3), false, 'too few reads to judge');
  assert.equal(pace.noteOutcome(10, 10), true);
  assert.equal(pace.noteOutcome(10, 0), false, 'the window was cleared: the slower rate starts clean');
  assert.equal(pace.perMinute, 12);
});

test('after a block the rate it was running at caps later scans, and what ran clean is where they start', () => {
  let now = 1_000_000;
  const store = memoryStore();
  const first = new AdaptivePace({ start: 14, max: 40, store, now: () => now, sleep: async () => {}, jitter: 0 });
  first._set(30);
  first.noteBlocked();
  assert.equal(first.perMinute, 15);
  assert.equal(store.get().blockedAt.rate, 30);

  // A new scan an hour later: capped at 75% of the rate that got us blocked.
  now += 60 * 60 * 1000;
  const second = new AdaptivePace({ start: 14, max: 40, store, now: () => now, sleep: async () => {}, jitter: 0 });
  assert.equal(second.max, 23, '30 x 0.75, rounded');
  assert.equal(second.learnedCap, 23);

  // Long after, the memory has expired.
  now += 13 * 60 * 60 * 1000;
  const third = new AdaptivePace({ start: 14, max: 40, store, now: () => now, sleep: async () => {}, jitter: 0 });
  assert.equal(third.max, 40);
  assert.equal(third.learnedCap, null);
});

test('a rate held for half an hour without trouble is remembered as the next scan\'s starting point', () => {
  let now = 0;
  const store = memoryStore();
  const pace = new AdaptivePace({ start: 20, max: 30, store, now: () => now, sleep: async () => {}, jitter: 0, stepEveryMs: 10 ** 9 });
  now += 31 * 60 * 1000;
  pace.noteHealthy();
  assert.equal(store.get().healthy.rate, 20);
  const next = new AdaptivePace({ start: 14, max: 30, store, now: () => now, sleep: async () => {}, jitter: 0 });
  assert.equal(next.perMinute, 17, 'starts at 85% of the proven rate');
});

test('a broken or missing memory file never stops a scan', () => {
  const broken = { load: () => { throw new Error('unreadable'); }, save: () => { throw new Error('read-only'); } };
  const pace = new AdaptivePace({ start: 14, max: 30, store: broken, now: () => 0, sleep: async () => {}, jitter: 0 });
  assert.equal(pace.perMinute, 14);
  pace.noteBlocked();
  assert.equal(pace.perMinute, 7);
});
