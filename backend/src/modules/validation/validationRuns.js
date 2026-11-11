/**
 * Saved record of each automatic validation run (WhatsApp or email) — its
 * scope and how far it got — so a run that was cancelled, stopped for a safety
 * reason, or lost to a backend restart can be resumed.
 *
 *   validationRuns/{id} = {
 *     kind: 'whatsapp' | 'email',
 *     collection: 'leads' | 'websiteLeads' | 'archive',
 *     category, states[], recheck,
 *     archiveId,                       // collection 'archive' only: the Excel archive validated,
 *     status: 'running' | 'done' | 'stopped',
 *     total, checked, found, stoppedReason,
 *     startedAt, updatedAt,            // epoch ms
 *     instance: { host, boot },        // which backend process was running it
 *   }
 *
 * The leads' own check flags are what make a resume pick up where the run left
 * off (an already-checked lead is skipped), so a resume simply starts the same
 * scope again — this record is what remembers the scope, and shows the run as
 * unfinished.
 */

import crypto from 'node:crypto';
import os from 'node:os';
import { getFirestore } from '../../firebase/admin.js';

const COLLECTION = 'validationRuns';

/** A "running" run that has not saved for this long is treated as interrupted. */
export const STALE_AFTER_MS = 30 * 1000;
/** Unfinished runs older than this are not offered any more. */
export const KEEP_MS = 14 * 24 * 60 * 60 * 1000;
const TICK_MS = 5000;

/** Who is writing: this process. A run still "running" from an EARLIER process is dead. */
const INSTANCE = { host: os.hostname(), boot: crypto.randomUUID() };

/** `running` | `done` | `stopped` | `interrupted` (it said running, but nothing is running it). */
export function effectiveStatus(run, now = Date.now(), instance = INSTANCE) {
  if (run.status !== 'running') return run.status;
  const mine = run.instance?.host === instance.host && run.instance?.boot === instance.boot;
  if (!mine) return 'interrupted';
  return now - (run.updatedAt || 0) > STALE_AFTER_MS ? 'interrupted' : 'running';
}

export const isResumable = (status) => status === 'stopped' || status === 'interrupted';

export async function saveRun(run, { db = getFirestore() } = {}) {
  await db.collection(COLLECTION).doc(run.id).set(run, { merge: true });
}

export async function loadRun(id, { db = getFirestore() } = {}) {
  const snap = await db.collection(COLLECTION).doc(id).get();
  return snap.exists ? { id, ...snap.data() } : null;
}

export async function deleteRun(id, { db = getFirestore() } = {}) {
  await db.collection(COLLECTION).doc(id).delete();
}

/** Unfinished runs (stopped or interrupted), newest first; optionally one [collection] and [kind]. */
export async function listUnfinished({ collection, kind, db = getFirestore(), now = Date.now() } = {}) {
  const snap = await db.collection(COLLECTION).get();
  return snap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .map((run) => ({ ...run, status: effectiveStatus(run, now) }))
    .filter((run) => isResumable(run.status))
    .filter((run) => now - (run.updatedAt || run.startedAt || 0) < KEEP_MS)
    .filter((run) => (!collection || run.collection === collection) && (!kind || run.kind === kind))
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
}

/**
 * Starts recording a run that has just been started. It polls [getSnapshot]
 * (the job's progress) every few seconds and, when the job ends, records
 * whether it finished (`done`) or stopped early (`stopped`: cancelled, or
 * halted for a safety reason).
 *
 * Never throws and never holds up the run: a failure to save is logged.
 *
 * @returns {string} the run's id
 */
export function trackRun({
  kind,
  collection,
  category = null,
  states = [],
  recheck = false,
  extra = {},
  getSnapshot,
  save = saveRun,
  now = Date.now,
  tickMs = TICK_MS,
}) {
  const id = crypto.randomUUID();
  const startedAt = now();
  // Identifies THIS job: a later job replaces the snapshot with its own.
  const jobStartedAt = getSnapshot()?.startedAt;
  const base = { id, kind, collection, category, states, recheck, ...extra, startedAt, instance: INSTANCE };

  const write = (snap, status) =>
    Promise.resolve(
      save({
        ...base,
        status,
        total: snap?.total ?? 0,
        checked: snap?.checked ?? 0,
        found: snap?.validCount ?? 0,
        stoppedReason: snap?.stoppedReason ?? null,
        updatedAt: now(),
      }),
    ).catch((err) => console.warn(`[validation-runs] could not save run ${id}: ${err?.message || err}`));

  let last = getSnapshot();
  write(last, 'running');

  const timer = setInterval(() => {
    const snap = getSnapshot();
    const sameJob = snap && snap.startedAt === jobStartedAt;
    if (sameJob) last = snap;
    // The job is over when it says so, or when another job has taken its place.
    if (sameJob && snap.status === 'running') {
      write(snap, 'running');
      return;
    }
    clearInterval(timer);
    const finished = last?.status === 'done' && !last?.stoppedReason;
    write(last, finished ? 'done' : 'stopped');
  }, tickMs);
  timer.unref?.();
  return id;
}

export const _COLLECTION = COLLECTION;
export const _INSTANCE = INSTANCE;
