/**
 * `job_search_queue` — the persistent queue of search combinations.
 *
 * One document per (run, combination), id `{runId}_{combinationKey}`, so
 * enqueuing the same combination twice for a run is impossible (`create`
 * fails on an existing id). Because the queue lives in Firestore, a run
 * survives a restart: tasks that were mid-flight are released back to
 * `pending` and picked up again.
 *
 *   pending ──claim──► running ──► done | failed | skipped
 *        ▲                │
 *        └── release ◄────┘   (pause/stop/crash)
 *
 * A claim is a transaction (pending → running with an owner and a lease), so
 * two workers — or two server instances — can never execute the same task.
 */

import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS } from '../models/constants.js';
import { stripUndefined, commitInBatches, toMillis } from './firestoreUtil.js';

const LEASE_MS = 10 * 60_000;

export function createQueueStore({ db = null, now = () => new Date() } = {}) {
  const database = () => db || getFirestore();
  const col = () => database().collection(COLLECTIONS.queue);
  const idOf = (runId, key) => `${runId}_${key}`;
  const data = (snap) => ({ id: snap.id, ...snap.data() });

  return {
    /**
     * Adds combinations to a run's queue. Safe to call again for the same run
     * (existing combinations are left alone); returns how many were added.
     * @param {Iterable<object>} combos  from combinations.js
     */
    async enqueue(runId, searchId, combos, { startSeq = 0 } = {}) {
      const stamp = now();
      let seq = startSeq;
      let added = 0;
      const items = [];
      for (const c of combos) items.push({ ...c, seq: seq++ });
      // `create` per document so a repeated enqueue doesn't reset finished tasks.
      for (let i = 0; i < items.length; i += 400) {
        const slice = items.slice(i, i + 400);
        const refs = slice.map((c) => col().doc(idOf(runId, c.key)));
        const existing = await database().getAll(...refs);
        const batch = database().batch();
        let inBatch = 0;
        slice.forEach((c, k) => {
          if (existing[k].exists) return;
          inBatch += 1;
          batch.create(refs[k], stripUndefined({
            runId, searchId, key: c.key, seq: c.seq,
            countryCode: c.countryCode, country: c.country, state: c.state, city: c.city, remoteOnly: c.remoteOnly, title: c.title,
            status: 'pending', attempts: 0, owner: null, leaseUntil: null,
            result: null, error: null, createdAt: stamp, startedAt: null, finishedAt: null,
          }));
        });
        if (inBatch) {
          await batch.commit();
          added += inBatch;
        }
      }
      return added;
    },

    /** Atomically takes up to [n] pending tasks (lowest `seq` first) for [owner]. */
    async claim(runId, owner, n = 1, { leaseMs = LEASE_MS } = {}) {
      const claimed = [];
      // Another claimer may win some of the candidates; look again (a few times) before giving up.
      for (let round = 0; round < 4 && claimed.length < n; round++) {
        const candidates = (await col().where('runId', '==', runId).where('status', '==', 'pending').orderBy('seq', 'asc').limit(n * 2).get()).docs;
        if (!candidates.length) break;
        for (const doc of candidates) {
          if (claimed.length >= n) break;
          const took = await database().runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists || fresh.data().status !== 'pending') return null;
            const stamp = now();
            const patch = { status: 'running', owner, leaseUntil: new Date(stamp.getTime() + leaseMs), startedAt: stamp, attempts: (fresh.data().attempts || 0) + 1 };
            tx.update(doc.ref, patch);
            return { id: doc.id, ...fresh.data(), ...patch };
          });
          if (took) claimed.push(took);
        }
      }
      return claimed;
    },

    async complete(id, { status = 'done', result = null, error = null } = {}) {
      await col().doc(id).set(stripUndefined({ status, result, error, owner: null, leaseUntil: null, finishedAt: now() }), { merge: true });
    },

    /** Puts tasks back to pending (pause/stop released their buffer, or a crashed worker's lease). */
    async release(ids) {
      await commitInBatches(database(), ids, (batch, id) => batch.set(col().doc(id), { status: 'pending', owner: null, leaseUntil: null }, { merge: true }));
    },

    /** Running tasks whose lease expired (or all of the run's, with `force`) go back to pending. */
    async releaseStale(runId, { force = false } = {}) {
      const running = (await col().where('runId', '==', runId).where('status', '==', 'running').get()).docs;
      const t = now().getTime();
      const stale = running.filter((d) => force || (toMillis(d.data().leaseUntil) ?? 0) < t);
      await this.release(stale.map((d) => d.id));
      return stale.length;
    },

    /** Failed tasks go back to pending for another try. */
    async requeueFailed(runId) {
      const failed = (await col().where('runId', '==', runId).where('status', '==', 'failed').get()).docs;
      await commitInBatches(database(), failed, (batch, d) => batch.set(d.ref, { status: 'pending', error: null, finishedAt: null }, { merge: true }));
      return failed.length;
    },

    async counts(runId) {
      const one = async (status) => (await col().where('runId', '==', runId).where('status', '==', status).count().get()).data().count;
      const [pending, running, done, failed, skipped] = await Promise.all(['pending', 'running', 'done', 'failed', 'skipped'].map(one));
      return { pending, running, done, failed, skipped, total: pending + running + done + failed + skipped };
    },

    async failedSample(runId, limit = 20) {
      const snap = await col().where('runId', '==', runId).where('status', '==', 'failed').limit(limit).get();
      return snap.docs.map(data);
    },

    async deleteRun(runId) {
      const snap = await col().where('runId', '==', runId).get();
      await commitInBatches(database(), snap.docs, (batch, d) => batch.delete(d.ref));
      return snap.size;
    },

    async get(id) {
      const snap = await col().doc(id).get();
      return snap.exists ? data(snap) : null;
    },
  };
}
