/**
 * Saved progress of no-website scans, so a scan that was stopped, crashed or
 * lost to a restart can be resumed without redoing the cities it covered.
 *
 * (A 1-star scan resumes from its Excel archive; a no-website scan has no
 * archive — its leads go straight to `websiteLeads` — so its progress is kept
 * here.)
 *
 *   noWebsiteScans/{runId}              = meta: categories, coverage, status, totals, times
 *   noWebsiteScanProgress/{runId}__{cat} = { covered: {State: [city…]}, stats: {State: {leads, businesses}} }
 *
 * Progress is one document per category so a long multi-category run stays far
 * below Firestore's 1 MB document limit. Times are epoch milliseconds.
 */

import crypto from 'node:crypto';
import os from 'node:os';
import { getFirestore } from '../../firebase/admin.js';

const RUNS = 'noWebsiteScans';
const PROGRESS = 'noWebsiteScanProgress';

/**
 * A "running" run that has not saved for this long is treated as interrupted.
 * A live scan saves a heartbeat every 15 s, so this only trips when it died.
 */
export const STALE_AFTER_MS = 60 * 1000;

/** Who is writing: this process. A run still "running" from an EARLIER process on this machine is dead. */
const INSTANCE = { host: os.hostname(), boot: crypto.randomUUID() };

const progressId = (runId, category) => `${runId}__${encodeURIComponent(category)}`;

/**
 * What a run's status really is: `running` only while it keeps saving progress.
 * One that stopped saving without finishing was cut off.
 */
export function effectiveStatus(run, now = Date.now(), instance = INSTANCE) {
  if (run?.status === 'running') {
    // Left "running" by a previous backend process on this machine (a restart): it cannot still be going.
    if (run.host === instance.host && run.boot && run.boot !== instance.boot) return 'interrupted';
    // Otherwise (another machine, or no owner recorded) only a long silence proves it died.
    if (now - (run.updatedAt || 0) > STALE_AFTER_MS) return 'interrupted';
  }
  return run?.status || 'stopped';
}

/** Only unfinished runs can be resumed. */
export const isResumable = (status) => status === 'stopped' || status === 'interrupted';

/**
 * Upserts a run's meta and its per-category progress.
 * @param {object} meta - { id, categories, coverage, concurrency, maxResultsPerCity, status, startedAt, updatedAt, finishedAt, totals }
 * @param {Record<string, {covered: object, stats: object}>} progress - by category
 */
export async function saveRun(meta, progress = {}, { db = getFirestore() } = {}) {
  if (!meta?.id) throw new Error('run id is required');
  await db.collection(RUNS).doc(meta.id).set({ ...meta, mode: 'no_website', host: INSTANCE.host, boot: INSTANCE.boot }, { merge: true });
  for (const [category, p] of Object.entries(progress)) {
    // Replaced, not merged: a city list that shrank must not keep stale entries.
    await db.collection(PROGRESS).doc(progressId(meta.id, category)).set({
      runId: meta.id,
      category,
      covered: p.covered || {},
      stats: p.stats || {},
      updatedAt: meta.updatedAt,
    });
  }
}

function summarize(run, now) {
  const totals = run.totals || {};
  const status = effectiveStatus(run, now);
  return {
    id: run.id,
    mode: 'no_website',
    categories: run.categories || [],
    coverage: run.coverage || 'standard',
    status,
    startedAt: run.startedAt || null,
    updatedAt: run.updatedAt || null,
    citiesTotal: totals.citiesTotal || 0,
    citiesDone: totals.citiesDone || 0,
    leads: totals.leads || 0,
    businesses: totals.businesses || 0,
    percent: totals.citiesTotal ? Math.min(100, Math.round(((totals.citiesDone || 0) / totals.citiesTotal) * 100)) : 0,
  };
}

/** Unfinished runs, newest first. */
export async function listResumableRuns({ db = getFirestore(), now = Date.now() } = {}) {
  const snap = await db.collection(RUNS).get();
  return snap.docs
    .map((d) => d.data())
    .filter((run) => run?.mode === 'no_website' && isResumable(effectiveStatus(run, now)))
    .map((run) => summarize(run, now))
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
}

/** A run with its saved progress, or `null`. */
export async function loadRun(id, { db = getFirestore(), now = Date.now() } = {}) {
  const snap = await db.collection(RUNS).doc(id).get();
  if (!snap.exists) return null;
  const run = snap.data();
  const progress = {};
  for (const category of run.categories || []) {
    const p = await db.collection(PROGRESS).doc(progressId(id, category)).get();
    progress[category] = p.exists ? { covered: p.data().covered || {}, stats: p.data().stats || {} } : { covered: {}, stats: {} };
  }
  return { ...run, status: effectiveStatus(run, now), progress };
}

export async function deleteRun(id, { db = getFirestore() } = {}) {
  const snap = await db.collection(RUNS).doc(id).get();
  if (!snap.exists) return false;
  for (const category of snap.data().categories || []) {
    await db.collection(PROGRESS).doc(progressId(id, category)).delete();
  }
  await db.collection(RUNS).doc(id).delete();
  return true;
}

export const _COLLECTIONS = { RUNS, PROGRESS };
export const _INSTANCE = INSTANCE;
