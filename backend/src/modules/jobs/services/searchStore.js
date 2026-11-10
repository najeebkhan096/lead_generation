/** `job_searches` — saved search configurations (what to look for, where, how). */

import crypto from 'node:crypto';
import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS } from '../models/constants.js';
import { notFound } from '../utils/errors.js';
import { serialize, stripUndefined, toMillis } from './firestoreUtil.js';
import { pagedQuery } from './paging.js';

export function createSearchStore({ db = null, now = () => new Date() } = {}) {
  const col = () => (db || getFirestore()).collection(COLLECTIONS.searches);
  const api = (snap) => serialize({ id: snap.id, ...snap.data() });

  return {
    async create(config) {
      const id = `s_${crypto.randomBytes(8).toString('hex')}`;
      const stamp = now();
      const doc = { ...config, createdAt: stamp, updatedAt: stamp, lastRunAt: null, lastRunId: null, lastRunStatus: null };
      await col().doc(id).create(stripUndefined(doc));
      return api(await col().doc(id).get());
    },

    async get(id) {
      const snap = await col().doc(String(id)).get();
      if (!snap.exists) throw notFound('Search not found');
      return snap;
    },

    async getData(id) {
      return (await this.get(id)).data();
    },

    async getApi(id) {
      return api(await this.get(id));
    },

    async update(id, config) {
      const ref = col().doc(String(id));
      const snap = await ref.get();
      if (!snap.exists) throw notFound('Search not found');
      const prev = snap.data();
      // Keep the schedule's bookkeeping when the schedule itself isn't changed.
      const schedule = { ...config.schedule, lastRunDate: config.schedule?.lastRunDate ?? prev.schedule?.lastRunDate ?? null };
      await ref.set(stripUndefined({ ...config, schedule, updatedAt: now() }), { merge: true });
      return api(await ref.get());
    },

    async remove(id) {
      const ref = col().doc(String(id));
      const snap = await ref.get();
      if (!snap.exists) throw notFound('Search not found');
      await ref.delete();
      return { id: snap.id };
    },

    async list({ limit, cursor } = {}) {
      const page = await pagedQuery({ db: db || getFirestore(), collection: COLLECTIONS.searches, sortField: 'updatedAt', limit, cursor, mapDoc: api });
      return page;
    },

    /** Searches whose daily schedule is switched on (small collection: filtered in memory). */
    async listScheduled() {
      const snap = await col().where('schedule.enabled', '==', true).get();
      return snap.docs.filter((d) => d.data().enabled !== false).map((d) => ({ id: d.id, ...d.data() }));
    },

    async markRun(id, { runId, status, date = null }) {
      const patch = { lastRunAt: now(), lastRunId: runId, lastRunStatus: status, updatedAt: now() };
      if (date) patch.schedule = { lastRunDate: date };
      await col().doc(String(id)).set(patch, { merge: true });
    },

    toMillis,
  };
}
