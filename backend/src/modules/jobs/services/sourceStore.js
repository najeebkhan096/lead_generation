/**
 * `job_sources` — per-source configuration and integration status.
 *
 * Holds what an operator may change (enabled, request limits, board tokens,
 * career pages) and what the engine learns (today's request usage, last
 * success/failure). It never holds API keys: those come from environment
 * variables only, and the API reports just whether they are set.
 */

import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS } from '../models/constants.js';
import { serialize, stripUndefined } from './firestoreUtil.js';

export function createSourceStore({ db = null, now = () => new Date() } = {}) {
  const col = () => (db || getFirestore()).collection(COLLECTIONS.sources);

  return {
    /** Stored docs by id (missing sources simply aren't present). */
    async all() {
      const snap = await col().get();
      return new Map(snap.docs.map((d) => [d.id, d.data()]));
    },

    async get(id) {
      const snap = await col().doc(id).get();
      return snap.exists ? snap.data() : null;
    },

    async update(id, patch) {
      await col().doc(id).set(stripUndefined({ ...patch, id, updatedAt: now() }), { merge: true });
      return serialize((await col().doc(id).get()).data());
    },

    async saveUsage(id, usage) {
      await col().doc(id).set({ id, usage: { date: usage.date, requests: usage.requests }, updatedAt: now() }, { merge: true });
    },

    /** After a source was used in a run: remember success or the last failure. */
    async recordOutcome(id, { ok, error = null }) {
      const stamp = now();
      const prev = (await col().doc(id).get()).data() || {};
      const status = {
        lastRunAt: stamp,
        lastSuccessAt: ok ? stamp : prev.status?.lastSuccessAt ?? null,
        lastError: ok ? null : error,
        consecutiveFailures: ok ? 0 : (prev.status?.consecutiveFailures || 0) + 1,
      };
      await col().doc(id).set(stripUndefined({ id, status, updatedAt: stamp }), { merge: true });
    },
  };
}
