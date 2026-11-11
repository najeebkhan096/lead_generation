import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  startStateCityScan,
  resumeNoWebsiteScan,
  cancelStateCityJob,
  getStateCityJobSnapshot,
  _resetStateCityJobForTests,
  _scanStateCities as scanStateCities,
  _newStateRecord as newStateRecord,
} from './stateCityOrchestrator.js';
import * as store from './noWebsiteRunStore.js';
import { fakeDb } from './fakeFirestore.js';
import { Mutex } from '../../lib/asyncMutex.js';
import { useChromium } from '../../scraper/domTestHarness.js';

const domTest = useChromium(); // a scan opens a (plain) browser even with a stub scraper
const backup = { ...process.env };
beforeEach(() => {
  process.env = { ...backup, MAPS_PERSISTENT_SESSION: 'false' };
  _resetStateCityJobForTests();
});

/** The run store bound to an in-memory database. */
function memoryStore(db = fakeDb()) {
  return {
    db,
    saves: [],
    saveRun(meta, progress) {
      this.saves.push({ meta, progress });
      return store.saveRun(meta, progress, { db });
    },
    loadRun: (id) => store.loadRun(id, { db }),
    listResumableRuns: () => store.listResumableRuns({ db }),
    deleteRun: (id) => store.deleteRun(id, { db }),
  };
}

const STATES = [
  { state: 'Texas', cities: ['Austin', 'Dallas', 'Houston'] },
  { state: 'Ohio', cities: ['Akron', 'Toledo'] },
];

async function untilDone() {
  for (let i = 0; i < 300; i++) {
    const snap = getStateCityJobSnapshot();
    if (snap?.status === 'done') return snap;
    await new Promise((r) => setTimeout(r, 50));
  }
  throw new Error('scan did not finish');
}

/** Counts one confirmed no-website business per city, like the real pipeline would. */
const onePerCity = async () => ({ missing: 1 });

// ── progress is saved while the scan runs (no browser needed) ────────────

function fakeJob(runStore, extra = {}) {
  return {
    concurrency: 1,
    dateRange: '30',
    maxResultsPerCity: 10,
    analyze: false,
    browser: null,
    cancelled: false,
    paused: false,
    requireSignIn: false,
    stoppedReason: null,
    mode: 'no_website',
    scrapeLocationFn: async () => [],
    seenPlaces: { Plumber: new Set() },
    activityLog: [],
    categories: ['Plumber'],
    runStore,
    runMutex: new Mutex(),
    runPersistMs: 10_000,
    runMeta: { id: 'r1', categories: ['Plumber'], coverage: 'extended', concurrency: 1, maxResultsPerCity: 10, startedAt: 1, citiesTotal: 3 },
    recordCityWebsitesFn: onePerCity,
    ...extra,
  };
}

test('the first covered city is saved at once; later ones are batched, then flushed by the timer', async () => {
  const rs = memoryStore();
  const job = fakeJob(rs, { runPersistMs: 40 });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas', 'Houston']);
  job.categoryStates = { Plumber: [rec] };
  await scanStateCities(job, 'Plumber', rec);
  await new Promise((r) => setTimeout(r, 120)); // let the batching timer fire

  assert.ok(rs.saves.length >= 1);
  assert.ok(rs.saves.length < 3, 'three cities did not cause three writes');
  const last = rs.saves.at(-1);
  assert.deepEqual(last.progress.Plumber.covered, { Texas: ['Austin', 'Dallas', 'Houston'] });
  assert.deepEqual(last.progress.Plumber.stats.Texas, { leads: 3, businesses: 0 });
  assert.equal(last.meta.totals.citiesDone, 3);
  assert.equal(last.meta.totals.leads, 3);
  assert.equal(last.meta.status, 'running');
});

test('a failing save is logged and never disturbs the scan', async () => {
  const rs = memoryStore();
  rs.saveRun = async () => {
    throw new Error('firestore unavailable');
  };
  const job = fakeJob(rs, { runPersistMs: 0 });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  job.categoryStates = { Plumber: [rec] };
  await scanStateCities(job, 'Plumber', rec);
  assert.equal(rec.status, 'done');
  assert.equal(rec.covered.length, 2);
  assert.ok(job.activityLog.some((l) => l.level === 'warn' && /Could not save the scan's progress/.test(l.message)));
});

test('a 1-star scan never saves run progress', async () => {
  const rs = memoryStore();
  const job = fakeJob(rs, { mode: 'reviews', runStore: null });
  const rec = newStateRecord('Texas', ['Austin']);
  job.categoryStates = { Plumber: [rec] };
  await scanStateCities(job, 'Plumber', rec);
  assert.equal(rs.saves.length, 0);
});

// ── resuming: refusals (no browser needed) ───────────────────────────────

const saved = (rs, meta, progress = {}) =>
  store.saveRun(
    { id: 'r1', categories: ['Plumber'], coverage: 'extended', concurrency: 1, maxResultsPerCity: 10, startedAt: 1, updatedAt: Date.now(), finishedAt: null, totals: {}, status: 'stopped', ...meta },
    progress,
    { db: rs.db }
  );

test('resuming an unknown scan is a 404', async () => {
  await assert.rejects(
    () => resumeNoWebsiteScan({ runId: 'nope', runStore: memoryStore(), statesOverride: STATES }),
    (err) => err.status === 404
  );
});

test('a finished scan cannot be resumed', async () => {
  const rs = memoryStore();
  await saved(rs, { status: 'done' });
  await assert.rejects(
    () => resumeNoWebsiteScan({ runId: 'r1', runStore: rs, statesOverride: STATES }),
    (err) => err.status === 400 && /already finished/.test(err.message)
  );
});

test('a scan that is still saving progress is not resumed underneath itself', async () => {
  const rs = memoryStore();
  await saved(rs, { status: 'running', updatedAt: Date.now() });
  await assert.rejects(
    () => resumeNoWebsiteScan({ runId: 'r1', runStore: rs, statesOverride: STATES }),
    (err) => err.status === 409
  );
});

test('with every city already covered there is nothing to resume', async () => {
  const rs = memoryStore();
  await saved(rs, {}, { Plumber: { covered: { Texas: ['Austin', 'Dallas', 'Houston'], Ohio: ['Akron', 'Toledo'] }, stats: {} } });
  await assert.rejects(
    () => resumeNoWebsiteScan({ runId: 'r1', runStore: rs, statesOverride: STATES }),
    (err) => err.status === 400 && /nothing left/.test(err.message)
  );
});

// ── stop, then resume: the whole round trip (needs a browser) ────────────

domTest('Stop then Resume: the second run searches only the cities the first did not cover, and the counts carry on', async () => {
  const rs = memoryStore();

  // Run 1 — Stop while Houston is being read.
  const first = [];
  await startStateCityScan({
    categories: ['Plumber'],
    mode: 'no_website',
    concurrency: 1,
    coverage: 'extended',
    statesOverride: STATES,
    runStore: rs,
    recordCityWebsitesFn: onePerCity,
    scrapeLocationFn: async (_c, location) => {
      first.push(location);
      if (location.startsWith('Houston')) cancelStateCityJob();
      const list = [];
      Object.defineProperty(list, 'searchStatus', { value: 'ok' });
      return list;
    },
  });
  const snap1 = await untilDone();
  assert.equal(snap1.cancelled, true);
  assert.ok(snap1.runId, 'the snapshot carries the run id the UI resumes by');
  assert.equal(first.length, 3, 'Austin, Dallas, then Houston where it was stopped');

  const [listed] = await rs.listResumableRuns();
  assert.equal(listed.id, snap1.runId);
  assert.equal(listed.status, 'stopped');
  assert.equal(listed.citiesDone, 2);
  assert.equal(listed.leads, 2);
  assert.equal(listed.citiesTotal, 5);

  // Run 2 — Resume.
  const second = [];
  const result = await resumeNoWebsiteScan({
    runId: snap1.runId,
    runStore: rs,
    statesOverride: STATES,
    scrapeLocationFn: async (_c, location) => {
      second.push(location);
      const list = [];
      Object.defineProperty(list, 'searchStatus', { value: 'ok' });
      return list;
    },
  });
  assert.equal(result.remaining, 3);
  assert.equal(result.runId, snap1.runId, 'the same run carries on');
  const snap2 = await untilDone();

  assert.equal(second.length, 3, 'only Houston, Akron and Toledo');
  assert.ok(second.every((l) => !/Austin|Dallas/.test(l)), 'covered cities are not searched again');
  const cat = snap2.categories[0];
  assert.equal(cat.citiesDone, 5);
  assert.equal(cat.statesDone, 2);
  assert.equal(cat.leadsCollected, 2, 'the first run\'s two leads are kept (this stub filed none for the new cities)');

  const run = await store.loadRun(snap1.runId, { db: rs.db });
  assert.equal(run.status, 'done', 'completing it marks the run finished');
  assert.deepEqual(await rs.listResumableRuns(), [], 'a finished scan is no longer offered for resume');
});

domTest('a scan that crashed mid-way (left "running") is offered as interrupted, and can be resumed', async () => {
  const rs = memoryStore();
  await store.saveRun(
    {
      id: 'crashed',
      categories: ['Plumber'],
      coverage: 'extended',
      concurrency: 1,
      maxResultsPerCity: 10,
      status: 'running',
      startedAt: 1,
      updatedAt: Date.now() - store.STALE_AFTER_MS - 1000,
      totals: { citiesDone: 3, citiesTotal: 5, leads: 3, businesses: 30 },
    },
    { Plumber: { covered: { Texas: ['Austin', 'Dallas', 'Houston'] }, stats: { Texas: { leads: 3, businesses: 30 } } } },
    { db: rs.db }
  );
  const [listed] = await rs.listResumableRuns();
  assert.equal(listed.status, 'interrupted');

  const seen = [];
  await resumeNoWebsiteScan({
    runId: 'crashed',
    runStore: rs,
    statesOverride: STATES,
    scrapeLocationFn: async (_c, location) => {
      seen.push(location);
      const list = [];
      Object.defineProperty(list, 'searchStatus', { value: 'ok' });
      return list;
    },
  });
  const snap = await untilDone();
  assert.equal(seen.length, 2, 'only Ohio\'s two cities were left');
  assert.equal(snap.categories[0].leadsCollected, 3, 'the earlier counts were restored');
  assert.equal(snap.categories[0].businessesProcessed, 30);
});

domTest('a no-website scan keeps saving a heartbeat while one slow city is still being read', async () => {
  const rs = memoryStore();
  await startStateCityScan({
    categories: ['Plumber'],
    mode: 'no_website',
    concurrency: 1,
    coverage: 'extended',
    statesOverride: [{ state: 'Texas', cities: ['Austin'] }],
    runStore: rs,
    runHeartbeatMs: 40,
    recordCityWebsitesFn: onePerCity,
    scrapeLocationFn: async () => {
      await new Promise((r) => setTimeout(r, 400)); // one slow city, no city completes meanwhile
      const list = [];
      Object.defineProperty(list, 'searchStatus', { value: 'ok' });
      return list;
    },
  });
  await untilDone();
  const running = rs.saves.filter((s) => s.meta.status === 'running');
  assert.ok(running.length >= 4, `expected several heartbeat saves during the 400 ms city, got ${running.length}`);
  assert.ok(running.at(-1).meta.updatedAt > running[0].meta.updatedAt, 'updatedAt moves forward');
  assert.equal(rs.saves.at(-1).meta.status, 'done', 'and the final save marks it finished');
});
