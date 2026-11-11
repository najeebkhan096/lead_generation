import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeDb } from './fakeFirestore.js';
import { saveRun, loadRun, listResumableRuns, deleteRun, effectiveStatus, isResumable, STALE_AFTER_MS, _COLLECTIONS, _INSTANCE } from './noWebsiteRunStore.js';

const NOW = 1_800_000_000_000;
const meta = (extra = {}) => ({
  id: 'run1',
  categories: ['Plumber', 'Dentist/Orthodontist'],
  coverage: 'extended',
  concurrency: 8,
  maxResultsPerCity: 160,
  status: 'running',
  startedAt: NOW - 3600_000,
  updatedAt: NOW,
  finishedAt: null,
  totals: { citiesDone: 30, citiesTotal: 120, leads: 12, businesses: 300 },
  ...extra,
});
const progress = () => ({
  Plumber: { covered: { Texas: ['Austin', 'Dallas'] }, stats: { Texas: { leads: 7, businesses: 80 } } },
  'Dentist/Orthodontist': { covered: { Ohio: ['Akron'] }, stats: {} },
});

test('a run is saved as one meta document plus one progress document per category', async () => {
  const db = fakeDb();
  await saveRun(meta(), progress(), { db });
  assert.equal(db.data.get(`${_COLLECTIONS.RUNS}/run1`).mode, 'no_website');
  const keys = [...db.data.keys()].filter((k) => k.startsWith(_COLLECTIONS.PROGRESS));
  assert.equal(keys.length, 2);
  assert.ok(keys.some((k) => k.endsWith('__Plumber')));
  assert.ok(keys.some((k) => k.endsWith(`__${encodeURIComponent('Dentist/Orthodontist')}`)), 'a "/" in a category name is safe in a document id');
});

test('loading a run returns its meta with the covered cities and counts per category', async () => {
  const db = fakeDb();
  await saveRun(meta({ status: 'stopped' }), progress(), { db });
  const run = await loadRun('run1', { db, now: NOW });
  assert.equal(run.status, 'stopped');
  assert.deepEqual(run.progress.Plumber.covered, { Texas: ['Austin', 'Dallas'] });
  assert.deepEqual(run.progress.Plumber.stats.Texas, { leads: 7, businesses: 80 });
  assert.deepEqual(run.progress['Dentist/Orthodontist'].covered, { Ohio: ['Akron'] });
  assert.equal(await loadRun('missing', { db }), null);
});

test('saving again replaces progress instead of keeping stale cities', async () => {
  const db = fakeDb();
  await saveRun(meta(), progress(), { db });
  await saveRun(meta({ updatedAt: NOW + 1 }), { Plumber: { covered: { Texas: ['Austin'] }, stats: {} }, 'Dentist/Orthodontist': { covered: {}, stats: {} } }, { db });
  const run = await loadRun('run1', { db, now: NOW + 1 });
  assert.deepEqual(run.progress.Plumber.covered, { Texas: ['Austin'] });
});

test('a run that stopped saving while "running" is reported as interrupted (crash or restart)', () => {
  assert.equal(effectiveStatus({ status: 'running', updatedAt: NOW }, NOW + 1000), 'running');
  assert.equal(effectiveStatus({ status: 'running', updatedAt: NOW }, NOW + STALE_AFTER_MS + 1), 'interrupted');
  assert.equal(effectiveStatus({ status: 'done', updatedAt: NOW }, NOW + STALE_AFTER_MS * 10), 'done');
  assert.ok(isResumable('stopped') && isResumable('interrupted'));
  assert.ok(!isResumable('running') && !isResumable('done'));
});

test('only unfinished runs are listed, newest first, with their progress', async () => {
  const db = fakeDb();
  await saveRun(meta({ id: 'old', status: 'stopped', updatedAt: NOW - 5000 }), {}, { db });
  await saveRun(meta({ id: 'new', status: 'stopped', updatedAt: NOW - 1000 }), {}, { db });
  await saveRun(meta({ id: 'finished', status: 'done' }), {}, { db });
  await saveRun(meta({ id: 'live', status: 'running', updatedAt: NOW }), {}, { db });
  await saveRun(meta({ id: 'crashed', status: 'running', updatedAt: NOW - STALE_AFTER_MS - 10 }), {}, { db });

  const runs = await listResumableRuns({ db, now: NOW });
  assert.deepEqual(runs.map((r) => r.id), ['new', 'old', 'crashed']);
  assert.equal(runs[2].status, 'interrupted');
  assert.equal(runs[0].percent, 25, '30 of 120 cities');
  assert.equal(runs[0].leads, 12);
  assert.deepEqual(runs[0].categories, ['Plumber', 'Dentist/Orthodontist']);
});

test('a 1-star run or anything not no-website is never listed', async () => {
  const db = fakeDb();
  await db.collection(_COLLECTIONS.RUNS).doc('x').set({ id: 'x', mode: 'reviews', status: 'stopped', categories: [] });
  assert.deepEqual(await listResumableRuns({ db, now: NOW }), []);
});

test('discarding removes the run and every category progress document', async () => {
  const db = fakeDb();
  await saveRun(meta({ status: 'stopped' }), progress(), { db });
  assert.equal(await deleteRun('run1', { db }), true);
  assert.equal(db.data.size, 0);
  assert.equal(await deleteRun('run1', { db }), false, 'discarding twice is harmless');
});

test('a run without an id is refused', async () => {
  await assert.rejects(() => saveRun({ categories: [] }, {}, { db: fakeDb() }), /run id is required/);
});

test('a run left "running" by an earlier backend process on this machine is interrupted at once', async () => {
  const db = fakeDb();
  // Written by a previous process: same host, different boot — saved a moment ago, so not "stale".
  await db.collection(_COLLECTIONS.RUNS).doc('prev').set({
    ...meta({ id: 'prev', status: 'running', updatedAt: NOW - 1000 }),
    mode: 'no_website',
    host: _INSTANCE.host,
    boot: 'a-previous-process',
  });
  assert.equal(effectiveStatus(await (await db.collection(_COLLECTIONS.RUNS).doc('prev').get()).data(), NOW), 'interrupted');
  const [listed] = await listResumableRuns({ db, now: NOW });
  assert.equal(listed.id, 'prev', 'it is offered for resume without waiting for the stale window');
});

test('a run still being saved by THIS process is running, and one on another machine only expires by silence', () => {
  const mine = { status: 'running', updatedAt: NOW - 1000, host: _INSTANCE.host, boot: _INSTANCE.boot };
  assert.equal(effectiveStatus(mine, NOW), 'running');

  const elsewhere = { status: 'running', updatedAt: NOW - 1000, host: 'some-other-machine', boot: 'x' };
  assert.equal(effectiveStatus(elsewhere, NOW), 'running', 'could be a live scan on another backend');
  assert.equal(effectiveStatus({ ...elsewhere, updatedAt: NOW - STALE_AFTER_MS - 1 }, NOW), 'interrupted');
});

test('the heartbeat interval is shorter than the stale window, so a live scan never looks dead', () => {
  assert.ok(STALE_AFTER_MS >= 60_000);
});
