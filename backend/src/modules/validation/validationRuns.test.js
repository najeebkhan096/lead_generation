import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fakeDb } from '../scan/fakeFirestore.js';
import { effectiveStatus, isResumable, listUnfinished, saveRun, loadRun, trackRun, STALE_AFTER_MS, _INSTANCE } from './validationRuns.js';
import { toRunSummary } from './validationRunsController.js';

const NOW = 1_800_000_000_000;
const mine = _INSTANCE;
const run = (over = {}) => ({
  id: 'r1', kind: 'whatsapp', collection: 'websiteLeads', category: 'Cafe USA', states: ['TX'], status: 'running',
  total: 100, checked: 40, found: 12, startedAt: NOW - 60_000, updatedAt: NOW, instance: mine, ...over,
});

test('a run is interrupted when nothing is running it: another process, or a stale heartbeat', () => {
  assert.equal(effectiveStatus(run(), NOW), 'running');
  assert.equal(effectiveStatus(run({ updatedAt: NOW - STALE_AFTER_MS - 1 }), NOW), 'interrupted');
  assert.equal(effectiveStatus(run({ instance: { host: 'other', boot: 'x' } }), NOW), 'interrupted');
  assert.equal(effectiveStatus(run({ status: 'stopped' }), NOW), 'stopped');
  assert.equal(effectiveStatus(run({ status: 'done' }), NOW), 'done');
  assert.equal(isResumable('stopped') && isResumable('interrupted'), true);
  assert.equal(isResumable('running') || isResumable('done'), false);
});

test('only unfinished runs are offered, newest first, for the collection and kind asked', async () => {
  const db = fakeDb();
  await saveRun(run({ id: 'a', status: 'stopped', updatedAt: NOW - 1000 }), { db });
  await saveRun(run({ id: 'b', status: 'done' }), { db });
  await saveRun(run({ id: 'c', status: 'running', instance: { host: 'gone', boot: 'x' }, updatedAt: NOW - 500 }), { db }); // crashed
  await saveRun(run({ id: 'd', status: 'running' }), { db }); // alive
  await saveRun(run({ id: 'e', status: 'stopped', kind: 'email' }), { db });
  await saveRun(run({ id: 'f', status: 'stopped', collection: 'leads' }), { db });
  await saveRun(run({ id: 'g', status: 'stopped', updatedAt: NOW - 30 * 86400_000, startedAt: NOW - 30 * 86400_000 }), { db }); // too old

  const wa = await listUnfinished({ collection: 'websiteLeads', kind: 'whatsapp', db, now: NOW });
  assert.deepEqual(wa.map((r) => [r.id, r.status]), [['c', 'interrupted'], ['a', 'stopped']]);
  const mail = await listUnfinished({ collection: 'websiteLeads', kind: 'email', db, now: NOW });
  assert.deepEqual(mail.map((r) => r.id), ['e']);
  assert.deepEqual((await listUnfinished({ collection: 'leads', db, now: NOW })).map((r) => r.id), ['f']);
});

test('the summary the page shows is trimmed to what it needs', () => {
  const s = toRunSummary(run({ status: 'stopped', stoppedReason: 'Daily check limit reached' }));
  assert.deepEqual(Object.keys(s).sort(), ['archiveId', 'category', 'checked', 'collection', 'found', 'id', 'kind', 'startedAt', 'states', 'status', 'stoppedReason', 'total', 'updatedAt']);
  assert.equal(s.instance, undefined);
});

test('tracking: saves progress while the job runs, then done when it finishes cleanly', async () => {
  const saved = [];
  let snap = { status: 'running', startedAt: 7, total: 10, checked: 3, validCount: 1, stoppedReason: null };
  const id = trackRun({ kind: 'whatsapp', collection: 'websiteLeads', category: 'Cafe USA', states: ['TX'], getSnapshot: () => snap, save: async (r) => saved.push(r), tickMs: 5 });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(saved.at(-1).status, 'running');
  assert.equal(saved.at(-1).checked, 3);
  assert.equal(saved.at(-1).id, id);
  assert.deepEqual(saved.at(-1).states, ['TX']);

  snap = { ...snap, status: 'done', checked: 10, validCount: 6 };
  await new Promise((r) => setTimeout(r, 25));
  assert.equal(saved.at(-1).status, 'done');
  assert.equal(saved.at(-1).found, 6);
  const count = saved.length;
  await new Promise((r) => setTimeout(r, 25));
  assert.equal(saved.length, count, 'stops saving once the job is over');
});

test('tracking: a cancelled run, or one halted for a safety reason, is stopped (resumable), not done', async () => {
  for (const end of [{ status: 'cancelled' }, { status: 'done', stoppedReason: 'Daily check limit reached' }]) {
    const saved = [];
    let snap = { status: 'running', startedAt: 1, total: 10, checked: 2, validCount: 0 };
    trackRun({ kind: 'email', collection: 'websiteLeads', getSnapshot: () => snap, save: async (r) => saved.push(r), tickMs: 5 });
    snap = { ...snap, ...end, checked: 4 };
    await new Promise((r) => setTimeout(r, 25));
    assert.equal(saved.at(-1).status, 'stopped');
    assert.equal(saved.at(-1).checked, 4);
  }
});

test('tracking: a failure to save never breaks the run', async () => {
  const snap = { status: 'done', startedAt: 1, total: 1, checked: 1 };
  trackRun({ kind: 'whatsapp', collection: 'leads', getSnapshot: () => snap, save: async () => { throw new Error('offline'); }, tickMs: 5 });
  await new Promise((r) => setTimeout(r, 20)); // no unhandled rejection
});

test('a saved run reads back', async () => {
  const db = fakeDb();
  await saveRun(run({ id: 'x' }), { db });
  assert.equal((await loadRun('x', { db })).category, 'Cafe USA');
  assert.equal(await loadRun('nope', { db }), null);
});
