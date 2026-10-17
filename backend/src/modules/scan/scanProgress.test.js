import { test } from 'node:test';
import assert from 'node:assert/strict';
import { completedCitiesFromStates, placeIdsFromLeads, applyResumeProgress, checkpointDue } from './scanProgress.js';
import { _scanStateCities as scanStateCities, _newStateRecord as newStateRecord } from './stateCityOrchestrator.js';
import { buildCoverage, describeCoverage, gridPoints, isCoverageTier } from '../../data/usCoverage.js';

const mapsUrl = (a, b) => `https://www.google.com/maps/place/X/data=!4m7!3m6!1s${a}:${b}!8m2?hl=en&gl=us`;

// ---- coverage ------------------------------------------------------------------------

test('standard coverage is the curated 10-per-state list; the tiers only add places', () => {
  const std = buildCoverage('standard');
  const ext = buildCoverage('extended');
  const max = buildCoverage('maximum');
  const count = (c) => c.reduce((n, s) => n + s.cities.length, 0);
  assert.equal(std.length, 51);
  assert.equal(count(std), 501);
  assert.ok(count(ext) > 1500 && count(ext) < 2000, `extended ${count(ext)}`);
  assert.ok(count(max) > count(ext) * 3, `maximum ${count(max)}`);
  for (const [i, s] of std.entries()) {
    for (const city of s.cities) {
      assert.ok(ext[i].cities.includes(city), `${s.state}: ${city} kept in extended`);
      assert.ok(max[i].cities.includes(city), `${s.state}: ${city} kept in maximum`);
    }
  }
});

test('no place is searched twice, and the curated order (largest cities) comes first', () => {
  for (const tier of ['extended', 'maximum']) {
    for (const s of buildCoverage(tier)) {
      const lower = s.cities.map((c) => c.toLowerCase());
      assert.equal(new Set(lower).size, lower.length, `${s.state} has duplicates in ${tier}`);
    }
  }
  assert.deepEqual(buildCoverage('extended')[0].cities.slice(0, 3), buildCoverage('standard')[0].cities.slice(0, 3));
});

test('places Census does not list (Hawaii, D.C.) still have their curated cities', () => {
  for (const tier of ['extended', 'maximum']) {
    const cov = buildCoverage(tier);
    assert.ok(cov.find((s) => s.state === 'Hawaii').cities.includes('Honolulu'));
    assert.ok(cov.find((s) => s.state === 'District of Columbia').cities.length >= 1);
  }
});

test('maximum coverage gives big cities a grid of search points; each has coordinates', () => {
  const tx = buildCoverage('maximum').find((s) => s.state === 'Texas');
  const grid = tx.cities.filter((c) => c.includes('· area'));
  assert.ok(grid.length > 100, 'Texas has several large cities');
  for (const name of grid.slice(0, 20)) {
    const spec = tx.specs[name];
    assert.ok(spec && Number.isFinite(spec.lat) && Number.isFinite(spec.lng) && spec.zoom, name);
    assert.ok(spec.lat > 25 && spec.lat < 37 && spec.lng < -93 && spec.lng > -107, `${name} is inside Texas`);
  }
  assert.deepEqual(buildCoverage('extended').find((s) => s.state === 'Texas').specs, {}, 'no grid below maximum');
});

test('a grid covers a city\'s extent without piling up, and a small city gets none', () => {
  assert.equal(gridPoints({ lat: 40, lng: -90, area: 2 }).length, 0, 'one search by name is enough');
  const houston = gridPoints({ lat: 29.78, lng: -95.39, area: 640 });
  assert.ok(houston.length > 20 && houston.length <= 60);
  assert.equal(new Set(houston.map((p) => `${p.lat},${p.lng}`)).size, houston.length, 'no repeated point');
});

test('the tiers are described with an honest size and time', () => {
  const d = describeCoverage('extended', 20);
  assert.equal(d.tier, 'extended');
  assert.ok(d.searches > 1500 && d.hours > 10);
  assert.equal(isCoverageTier('extended'), true);
  assert.equal(isCoverageTier('everything'), false);
  assert.throws(() => buildCoverage('everything'), /Unknown coverage/);
});

// ---- saving and restoring progress ------------------------------------------------------

test('covered cities are saved per state, and only for states that have some', () => {
  const a = newStateRecord('Texas', ['Austin', 'Dallas', 'Plano']);
  const b = newStateRecord('Ohio', ['Akron']);
  a.covered = ['Austin', 'Plano'];
  assert.deepEqual(completedCitiesFromStates([a, b]), { Texas: ['Austin', 'Plano'] });
});

test('resuming skips the cities already covered and restores the counts', () => {
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Plano', 'Waco']);
  const restored = applyResumeProgress([rec], { Texas: ['Austin', 'Plano', 'Gone City'] }, { Texas: [{}, {}, {}] });
  assert.equal(restored, 2, 'a saved city no longer in the list is ignored');
  assert.deepEqual(rec.covered, ['Austin', 'Plano']);
  assert.deepEqual(rec.pending, ['Dallas', 'Waco']);
  assert.equal(rec.leadsCollected, 3);
});

test('a resumed scan does not read a business it already has', () => {
  const ids = placeIdsFromLeads([{ mapsUrl: mapsUrl('0x1', '0xaa') }, { mapsUrl: mapsUrl('0x2', '0xbb') }, { mapsUrl: 'https://example.com' }, {}]);
  assert.deepEqual([...ids].sort(), ['0x1:0xaa', '0x2:0xbb']);
});

test('a resumed state only scans its remaining cities', async () => {
  const scanned = [];
  const job = {
    concurrency: 2, dateRange: '28', maxResultsPerCity: 10, cancelled: false, paused: false, requireSignIn: true,
    collectedLeadsByState: { Cafe: {} }, seenPlaces: { Cafe: new Set() }, activityLog: [],
    scrapeLocationFn: async (_c, location) => { scanned.push(location); return []; },
  };
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Plano', 'Waco']);
  applyResumeProgress([rec], { Texas: ['Austin', 'Plano'] });
  await scanStateCities(job, 'Cafe', rec);
  assert.deepEqual(scanned.map((l) => l.split(',')[0]).sort(), ['Dallas', 'Waco']);
  assert.equal(rec.status, 'done');
  assert.deepEqual(rec.covered.sort(), ['Austin', 'Dallas', 'Plano', 'Waco']);
});

test('a checkpoint is due after enough time or enough cities, never with nothing new', () => {
  const base = { now: 1_000_000, lastAt: 1_000_000, citiesSince: 0 };
  assert.equal(checkpointDue(base), false, 'nothing new');
  assert.equal(checkpointDue({ ...base, citiesSince: 5 }), false, 'too soon');
  assert.equal(checkpointDue({ ...base, citiesSince: 5, now: base.now + 11 * 60 * 1000 }), true, 'ten minutes');
  assert.equal(checkpointDue({ ...base, citiesSince: 40 }), true, '40 cities');
  assert.equal(checkpointDue({ ...base, citiesSince: 0, now: base.now + 99 * 60 * 1000 }), false);
});

test('while scanning, progress is saved every so many cities, one save at a time, without blocking', async () => {
  const saves = [];
  let release;
  const job = {
    concurrency: 1, dateRange: '28', maxResultsPerCity: 10, cancelled: false, paused: false, requireSignIn: true,
    collectedLeadsByState: { Cafe: {} }, seenPlaces: { Cafe: new Set() }, activityLog: [],
    scrapeLocationFn: async () => [],
    checkpointFn: (category) => { saves.push(category); return new Promise((r) => { release = r; }); },
  };
  const rec = newStateRecord('Texas', Array.from({ length: 100 }, (_, i) => `City ${i}`));
  await scanStateCities(job, 'Cafe', rec);
  assert.equal(rec.status, 'done', 'a slow save never held a worker up');
  assert.equal(saves.length, 1, 'the second save waited for the first to finish');
  release();
});

// ---- the browser dying mid-scan ---------------------------------------------------------

test('a dead browser is replaced before the next city, once, whatever the number of workers', async () => {
  // ensureBrowser only acts with the real scraper; check its contract through a job that opts in.
  const { _ensureBrowserForTests } = await import('./stateCityOrchestrator.js');
  let launches = 0;
  const dead = { isAlive: () => false, close: async () => {} };
  const job = { browser: dead, activityLog: [] };
  const fresh = { isAlive: () => true, close: async () => {} };
  await Promise.all([1, 2, 3, 4].map(() => _ensureBrowserForTests(job, async () => { launches += 1; return fresh; })));
  assert.equal(launches, 1, 'one new browser, not four');
  assert.equal(job.browser, fresh);
  assert.ok(job.activityLog.some((l) => /browser stopped/.test(l.message)));
  await _ensureBrowserForTests(job, async () => { launches += 1; return fresh; });
  assert.equal(launches, 1, 'a healthy browser is left alone');
});

test('a resumed scan keeps the archive\'s coverage tier, so a second resume rebuilds the same cities', async () => {
  const { startStateCityScan, getStateCityJobSnapshot, _resetStateCityJobForTests } = await import('./stateCityOrchestrator.js');
  _resetStateCityJobForTests();
  process.env.MAPS_PERSISTENT_SESSION = 'false';
  await startStateCityScan({
    categories: ['Auto'],
    coverage: 'extended',
    statesOverride: [{ state: 'Texas', cities: ['Austin'], specs: {} }], // what a resume passes: only the states still needed
    requireSignIn: false,
    scrapeLocationFn: async () => [],
  });
  for (let i = 0; i < 100 && getStateCityJobSnapshot()?.status !== 'done'; i++) await new Promise((r) => setTimeout(r, 50));
  assert.equal(getStateCityJobSnapshot().coverage, 'extended');
});
