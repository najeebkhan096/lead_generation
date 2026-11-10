/**
 * `job_scan_runs` — one document per scan: what was asked, live progress
 * counters, per-source statistics and the recent errors. The scan engine
 * flushes it a few times a second at most; the UI polls it.
 */

import crypto from 'node:crypto';
import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS, ACTIVE_RUN_STATUSES } from '../models/constants.js';
import { notFound } from '../utils/errors.js';
import { serialize, stripUndefined, toMillis } from './firestoreUtil.js';
import { pagedQuery } from './paging.js';

export function createRunStore({ db = null, now = () => new Date() } = {}) {
  const database = () => db || getFirestore();
  const col = () => database().collection(COLLECTIONS.scanRuns);
  const api = (snap) => serialize({ id: snap.id, ...snap.data() });

  return {
    newId: () => `r_${now().toISOString().slice(0, 10).replace(/-/g, '')}_${crypto.randomBytes(5).toString('hex')}`,

    async create(run) {
      const stamp = now();
      await col().doc(run.id).create(stripUndefined({ ...run, createdAt: stamp, updatedAt: stamp }));
    },

    /** Merge-writes progress; dotted keys (`jobs.new`) are allowed via `set(…, {merge})` maps. */
    async patch(id, fields) {
      await col().doc(String(id)).set(stripUndefined({ ...fields, updatedAt: now() }), { merge: true });
    },

    async get(id) {
      const snap = await col().doc(String(id)).get();
      return snap.exists ? { id: snap.id, ...snap.data() } : null;
    },

    async getApi(id) {
      const snap = await col().doc(String(id)).get();
      if (!snap.exists) throw notFound('Scan run not found');
      return api(snap);
    },

    async list({ limit, cursor, searchId } = {}) {
      return pagedQuery({
        db: database(),
        collection: COLLECTIONS.scanRuns,
        where: searchId ? [['searchId', '==', searchId]] : [],
        sortField: 'createdAt',
        limit,
        cursor,
        mapDoc: api,
      });
    },

    /** Runs that still own work (queued/running/paused/stopping/interrupted). */
    async listActive() {
      const snaps = await Promise.all(ACTIVE_RUN_STATUSES.map((s) => col().where('status', '==', s).get()));
      return snaps.flatMap((s) => s.docs).map((d) => ({ id: d.id, ...d.data() }));
    },

    async findActiveForSearch(searchId) {
      const active = await this.listActive();
      return active.find((r) => r.searchId === searchId) || null;
    },

    /** Last N finished runs, newest first (for the success/failure statistics). */
    async recent(limit = 30) {
      const snap = await col().orderBy('createdAt', 'desc').limit(limit).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },

    toMillis,
  };
}
