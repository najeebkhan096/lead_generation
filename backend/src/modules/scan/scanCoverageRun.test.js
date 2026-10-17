import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { startStateCityScan, getStateCityJobSnapshot, _resetStateCityJobForTests } from './stateCityOrchestrator.js';
import { buildCoverage } from '../../data/usCoverage.js';
import { useChromium } from '../../scraper/domTestHarness.js';

const domTest = useChromium(); // the scan opens a (plain) browser even with a stub scraper
const backup = { ...process.env };
beforeEach(() => {
  process.env = { ...backup, MAPS_PERSISTENT_SESSION: 'false' };
  _resetStateCityJobForTests();
});

async function untilDone() {
  for (let i = 0; i < 600; i++) {
    const snap = getStateCityJobSnapshot();
    if (snap && snap.status === 'done') return snap;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('scan did not finish');
}

async function runCoverage(coverage) {
  const calls = [];
  await startStateCityScan({
    categories: ['Auto Repair'],
    coverage,
    concurrency: 6,
    dateRange: '28',
    requireSignIn: false,
    scrapeLocationFn: async (_category, location, options) => {
      const list = [];
      Object.defineProperty(list, 'searchStatus', { value: 'ok' });
      calls.push({ location, center: options.center, seen: options.seenPlaceIds, googleOnly: options.googleOnly });
      return list;
    },
  });
  return { calls, snap: await untilDone() };
}

domTest('extended coverage searches every place once, by name, and every state completes', async () => {
  const expected = buildCoverage('extended').reduce((n, s) => n + s.cities.length, 0);
  const { calls, snap } = await runCoverage('extended');
  assert.equal(calls.length, expected);
  assert.ok(calls.every((c) => !c.center), 'no grid below maximum');
  assert.ok(calls.every((c) => c.googleOnly === true));
  assert.equal(snap.coverage, 'extended');
  const cat = snap.categories[0];
  assert.equal(cat.statesDone, 51);
  assert.equal(cat.citiesDone, expected);
  assert.ok(snap.pace && snap.pace.perMinute > 0 && snap.pace.max >= snap.pace.perMinute, 'the pace is reported');
});

domTest('maximum coverage gives grid points their coordinates and shares one "already read" set', async () => {
  const cov = buildCoverage('maximum');
  const expected = cov.reduce((n, s) => n + s.cities.length, 0);
  const grid = cov.reduce((n, s) => n + Object.keys(s.specs).length, 0);
  assert.ok(grid > 1000);
  const { calls } = await runCoverage('maximum');
  assert.equal(calls.length, expected);
  assert.equal(calls.filter((c) => c.center).length, grid, 'every grid point is searched around its coordinates');
  const centered = calls.find((c) => c.center);
  assert.ok(Number.isFinite(centered.center.lat) && Number.isFinite(centered.center.lng) && centered.center.zoom);
  assert.equal(new Set(calls.map((c) => c.seen)).size, 1, 'one shared set for the whole category');
});

domTest('an unknown coverage is refused', async () => {
  await assert.rejects(
    () => startStateCityScan({ categories: ['x'], coverage: 'everything', requireSignIn: false, scrapeLocationFn: async () => [] }),
    (err) => err.status === 400 && /Unknown coverage/.test(err.message),
  );
});
