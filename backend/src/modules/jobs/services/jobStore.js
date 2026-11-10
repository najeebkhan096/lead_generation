/**
 * Jobs in Firestore: ingestion with duplicate detection, listing, updates.
 *
 * ── Duplicate detection ────────────────────────────────────────────────────
 * One posting can arrive from several sources and again on every scan, and
 * must stay ONE document. Each incoming job is resolved, in this order, to:
 *
 *   1. `job_keys/s|source|sourceJobId`   same source, same posting id
 *   2. `job_keys/u|canonicalApplyUrl`    same direct application URL
 *   3. `jobs/{fingerprint}`              same company + title + location
 *   4. `job_keys/ct|company|title`       a bucket of jobs with that company and
 *                                        title; the one with a near-identical
 *                                        description (MinHash) and a compatible
 *                                        location is the same job
 *
 * else it is new, with the fingerprint as its document id. The lookups for a
 * whole page of jobs are one batched read; each document is written once.
 *
 * Deleting a job leaves its lookup keys behind marked `deleted`, so the
 * posting is not silently re-added by the next scan.
 *
 * Writes are serialised by a mutex (this process is the only writer, see
 * lib/asyncMutex.js); `create()` on a new job id additionally guards against
 * a second process racing us, in which case the page is simply resolved again.
 */

import { Mutex } from '../../../lib/asyncMutex.js';
import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS, RAW_SUBCOLLECTION, JOB_SORTS, JOB_STATUSES, USER_STATES } from '../models/constants.js';
import { buildNewDoc, mergeDoc, rawPayload } from '../models/jobDoc.js';
import {
  fingerprintOf,
  applyUrlKey,
  bucketKey,
  keyDocId,
  sourceKey,
  urlKey,
  descriptionSignature,
  signatureSimilarity,
  locationsCompatible,
  SIMILARITY_THRESHOLD,
  companyKey,
} from '../utils/normalize.js';
import { fold } from '../utils/text.js';
import { silentLogger } from '../utils/logger.js';
import { notFound, invalid } from '../utils/errors.js';
import { getAllChunked, commitInBatches, stripUndefined, serialize, toDate, toMillis, isAlreadyExists } from './firestoreUtil.js';
import { pagedQuery, withIndexFallback } from './paging.js';

const BUCKET_LIMIT = 10;
const LIST_FIELDS_HIDDEN = ['description', 'descSig', 'responsibilities', 'sources', 'contentHash'];

/** What the list/detail endpoints return for a job document. */
export function jobToApi(snap, { detail = false } = {}) {
  const data = snap.data();
  const out = { id: snap.id, ...data };
  if (!detail) for (const f of LIST_FIELDS_HIDDEN) delete out[f];
  else {
    delete out.descSig;
    delete out.contentHash;
    out.sources = (data.sources || []).map(({ sourceRef, ...s }) => s);
  }
  if (!detail) out.sourceCount = (data.sources || []).length;
  return serialize(out);
}

/** Server-side filters backed by composite indexes, in the order they are preferred. */
function indexPlan(f) {
  if (f.companyKey) return [['companyKey', '==', f.companyKey]];
  if (f.countryCode) {
    const plan = [['countryCode', '==', f.countryCode]];
    if (f.state) {
      plan.push(['state', '==', f.state]);
      if (f.city) plan.push(['city', '==', f.city]);
    }
    return plan;
  }
  if (f.userState) return [['userState', '==', f.userState]];
  if (f.status) return [['status', '==', f.status]];
  return [];
}

const planFields = (plan) => plan.map(([field]) => field);

/** Everything the plan did not cover, applied to a (masked) document. */
function buildMemoryFilter(f, covered, now) {
  const checks = [];
  const eq = (field, value) => value != null && !covered.includes(field) && checks.push((d) => d[field] === value);
  eq('companyKey', f.companyKey);
  eq('countryCode', f.countryCode);
  eq('state', f.state);
  eq('city', f.city);
  eq('userState', f.userState);
  eq('status', f.status);
  eq('experienceLevel', f.experienceLevel);
  eq('employmentType', f.employmentType);
  eq('workArrangement', f.workArrangement);
  if (f.source) checks.push((d) => (d.sourceNames || []).includes(f.source));
  if (f.skills?.length) {
    checks.push((d) => {
      const have = new Set([...(d.requiredSkills || []), ...(d.preferredSkills || [])].map((s) => s.toLowerCase()));
      return f.skills.every((s) => have.has(s.toLowerCase()));
    });
  }
  if (f.salaryMin != null) {
    checks.push((d) => d.salaryMaxAnnual != null && d.salaryMaxAnnual >= f.salaryMin && (!f.salaryCurrency || d.salaryCurrency === f.salaryCurrency));
  }
  if (f.postedWithinDays) {
    const since = now.getTime() - f.postedWithinDays * 86_400_000;
    checks.push((d) => (toMillis(d.sortAt) ?? 0) >= since);
  }
  if (f.discoveredWithinDays) {
    const since = now.getTime() - f.discoveredWithinDays * 86_400_000;
    checks.push((d) => (toMillis(d.discoveredAt) ?? 0) >= since);
  }
  if (f.runId) checks.push((d) => d.lastRunId === f.runId || d.discoveredBy?.runId === f.runId);
  if (f.q) {
    const words = fold(f.q).split(' ').filter(Boolean);
    checks.push((d) => {
      const hay = fold([d.title, d.companyName, d.locationText, d.city, d.state, ...(d.requiredSkills || [])].join(' '));
      return words.every((w) => hay.includes(w));
    });
  }
  if (f.company) {
    const needle = fold(f.company);
    checks.push((d) => fold(d.companyName).includes(needle));
  }
  return checks.length ? (d) => checks.every((c) => c(d)) : null;
}

const SCAN_FIELDS = [
  'companyKey', 'countryCode', 'state', 'city', 'userState', 'status', 'experienceLevel', 'employmentType', 'workArrangement',
  'sourceNames', 'requiredSkills', 'preferredSkills', 'salaryMaxAnnual', 'salaryCurrency', 'sortAt', 'discoveredAt', 'lastRunId',
  'discoveredBy', 'title', 'companyName', 'locationText',
];

export function createJobStore({ db = null, now = () => new Date(), log = silentLogger, mutex = new Mutex() } = {}) {
  const getDb = () => db || getFirestore();
  const jobs = () => getDb().collection(COLLECTIONS.jobs);
  const keys = () => getDb().collection(COLLECTIONS.keys);

  // ------------------------------------------------------------- ingestion
  async function resolveAndWrite(incoming, ctx) {
    const database = getDb();
    const stamp = now();
    const items = incoming.map((job) => {
      const fp = fingerprintOf(job);
      const uKey = applyUrlKey(job.applyUrl);
      return {
        job,
        fp,
        sId: keyDocId(sourceKey(job.source, job.sourceJobId)),
        uId: uKey ? keyDocId(urlKey(uKey)) : null,
        bId: keyDocId(bucketKey(job)),
      };
    });

    // One batched read for everything the page might match.
    const refs = new Map(); // path -> ref
    const ref = (collection, id) => {
      const r = database.collection(collection).doc(id);
      refs.set(r.path, r);
      return r;
    };
    for (const it of items) {
      ref(COLLECTIONS.jobs, it.fp);
      ref(COLLECTIONS.keys, it.sId);
      if (it.uId) ref(COLLECTIONS.keys, it.uId);
      ref(COLLECTIONS.keys, it.bId);
    }
    const snaps = new Map((await getAllChunked(database, [...refs.values()])).map((s) => [s.ref.path, s]));
    const snap = (collection, id) => snaps.get(`${collection}/${id}`);

    // In-memory overlay so jobs of the same page merge with each other.
    const docs = new Map(); // jobId -> { data, isNew, raws: [] , touched }
    const keyWrites = new Map(); // keyId -> data
    const buckets = new Map(); // bucketId -> { jobIds, deletedFps }

    const loadJob = (id) => {
      if (docs.has(id)) return docs.get(id);
      const s = snap(COLLECTIONS.jobs, id);
      if (s?.exists) {
        docs.set(id, { data: s.data(), isNew: false, raws: [], touched: false });
        return docs.get(id);
      }
      return null;
    };

    // Jobs that the lookup keys point at (and the bucket candidates) need their own documents.
    const bucketData = (bId) => {
      if (buckets.has(bId)) return buckets.get(bId);
      const s = snap(COLLECTIONS.keys, bId);
      const data = s?.exists ? s.data() : { type: 'bucket', jobIds: [], deletedFps: [] };
      buckets.set(bId, { jobIds: [...(data.jobIds || [])], deletedFps: [...(data.deletedFps || [])], dirty: false });
      return buckets.get(bId);
    };
    const referenced = new Set();
    for (const it of items) {
      for (const keyId of [it.sId, it.uId]) {
        const k = keyId ? snap(COLLECTIONS.keys, keyId) : null;
        if (k?.exists && k.data().jobId && !k.data().deleted) referenced.add(k.data().jobId);
      }
      for (const jid of bucketData(it.bId).jobIds) referenced.add(jid);
    }
    const missing = [...referenced].filter((id) => !snaps.has(`${COLLECTIONS.jobs}/${id}`));
    if (missing.length) {
      const more = await getAllChunked(database, missing.map((id) => database.collection(COLLECTIONS.jobs).doc(id)));
      for (const s of more) snaps.set(s.ref.path, s);
    }

    const result = { new: 0, updated: 0, duplicate: 0, suppressed: 0, ids: [], outcomes: [] };

    for (const it of items) {
      const { job } = it;
      const sKeySnap = snap(COLLECTIONS.keys, it.sId);
      const uKeySnap = it.uId ? snap(COLLECTIONS.keys, it.uId) : null;
      const bucket = bucketData(it.bId);
      const writtenS = keyWrites.get(it.sId);
      const writtenU = it.uId ? keyWrites.get(it.uId) : null;

      // Deleted by the user: stay deleted.
      const sKey = writtenS || (sKeySnap?.exists ? sKeySnap.data() : null);
      const uKey = writtenU || (uKeySnap?.exists ? uKeySnap.data() : null);
      if (sKey?.deleted || uKey?.deleted || bucket.deletedFps.includes(it.fp)) {
        result.suppressed += 1;
        result.outcomes.push('suppressed');
        result.ids.push(null);
        continue;
      }

      let targetId = null;
      if (sKey?.jobId && loadJob(sKey.jobId)) targetId = sKey.jobId;
      else if (uKey?.jobId && loadJob(uKey.jobId)) targetId = uKey.jobId;
      else if (loadJob(it.fp)) targetId = it.fp;
      else {
        const sig = descriptionSignature(job.description);
        let best = null;
        for (const jid of bucket.jobIds) {
          const cand = loadJob(jid);
          if (!cand || !sig) continue;
          if (!locationsCompatible(cand.data, job)) continue;
          const similarity = signatureSimilarity(sig, cand.data.descSig);
          if (similarity >= SIMILARITY_THRESHOLD && (!best || similarity > best.similarity)) best = { jid, similarity };
        }
        if (best) targetId = best.jid;
      }

      let outcome;
      if (targetId) {
        const entry = docs.get(targetId);
        const merged = mergeDoc(entry.data, job, ctx, stamp);
        // A page that finds the same posting twice reports the second as a duplicate.
        outcome = entry.isNew || entry.touched ? 'duplicate' : merged.outcome;
        entry.data = merged.doc;
        entry.touched = true;
        if (outcome === 'updated' || merged.newSource || entry.isNew) entry.raws.push(rawPayload(job, stamp));
        result.ids.push(targetId);
      } else {
        const data = buildNewDoc(job, ctx, stamp);
        docs.set(it.fp, { data, isNew: true, raws: [rawPayload(job, stamp)], touched: true });
        targetId = it.fp;
        outcome = 'new';
        result.ids.push(targetId);
        if (!bucket.jobIds.includes(targetId)) {
          bucket.jobIds = [...bucket.jobIds, targetId].slice(-BUCKET_LIMIT);
          bucket.dirty = true;
        }
      }

      result[outcome] += 1;
      result.outcomes.push(outcome);

      // Remember how to find this job again (only when the key is new or points elsewhere).
      if (!(sKeySnap?.exists && sKeySnap.data().jobId === targetId)) {
        keyWrites.set(it.sId, { type: 'source', jobId: targetId, source: job.source, sourceJobId: String(job.sourceJobId), updatedAt: stamp });
      }
      if (it.uId && !(uKeySnap?.exists && uKeySnap.data().jobId === targetId)) {
        keyWrites.set(it.uId, { type: 'url', jobId: targetId, updatedAt: stamp });
      }
    }

    // ---- writes (one per document) ----
    const writes = [];
    for (const [id, entry] of docs) {
      if (!entry.touched) continue;
      writes.push({ kind: entry.isNew ? 'create' : 'set', ref: database.collection(COLLECTIONS.jobs).doc(id), data: stripUndefined(entry.data) });
      for (const raw of entry.raws) {
        writes.push({ kind: 'set', ref: database.collection(COLLECTIONS.jobs).doc(id).collection(RAW_SUBCOLLECTION).doc(`${raw.source}_${keyDocId(raw.sourceJobId).slice(0, 12)}`), data: stripUndefined(raw) });
      }
    }
    for (const [id, data] of keyWrites) writes.push({ kind: 'set', ref: database.collection(COLLECTIONS.keys).doc(id), data: stripUndefined(data) });
    for (const [id, b] of buckets) {
      if (b.dirty) {
        writes.push({ kind: 'set', ref: database.collection(COLLECTIONS.keys).doc(id), data: { type: 'bucket', jobIds: b.jobIds, deletedFps: b.deletedFps, updatedAt: stamp } });
      }
    }
    await commitInBatches(database, writes, (batch, w) => (w.kind === 'create' ? batch.create(w.ref, w.data) : batch.set(w.ref, w.data)));
    return result;
  }

  /**
   * Stores normalized jobs, merging duplicates.
   * @returns {Promise<{new: number, updated: number, duplicate: number, suppressed: number, ids: string[]}>}
   */
  async function upsertMany(incoming, ctx = {}) {
    const list = incoming || [];
    const indices = [];
    const valid = [];
    list.forEach((j, i) => {
      if (j?.title && j.companyName && j.source && j.sourceJobId != null) {
        indices.push(i);
        valid.push(j);
      }
    });
    const empty = { new: 0, updated: 0, duplicate: 0, suppressed: 0, ids: list.map(() => null), outcomes: list.map(() => 'invalid') };
    if (!valid.length) return empty;
    const run = () => resolveAndWrite(valid, ctx);
    const result = await mutex.runExclusive(async () => {
      try {
        return await run();
      } catch (err) {
        // Another process created one of "our new" ids between our read and write: resolve again.
        if (isAlreadyExists(err)) {
          log.warn('concurrent create detected; retrying page', { count: valid.length });
          return run();
        }
        throw err;
      }
    });
    // Outcomes line up with the input array (invalid entries are marked as such).
    const outcomes = list.map(() => 'invalid');
    const ids = list.map(() => null);
    indices.forEach((originalIndex, k) => {
      outcomes[originalIndex] = result.outcomes[k];
      ids[originalIndex] = result.ids[k];
    });
    return { ...result, outcomes, ids };
  }

  // --------------------------------------------------------------- reading
  async function get(id) {
    const snap = await jobs().doc(String(id)).get();
    return snap.exists ? snap : null;
  }

  async function getDetail(id) {
    const snap = await get(id);
    if (!snap) throw notFound('Job not found');
    return jobToApi(snap, { detail: true });
  }

  /**
   * @param {object} f  validated filters (validators/jobs.js)
   */
  async function list(f = {}) {
    const sort = JOB_SORTS[f.sort] || JOB_SORTS.discovered;
    const sortField = sort.field === 'postedAt' ? 'sortAt' : sort.field;
    const plan = indexPlan(f);
    const base = {
      db: getDb(),
      collection: COLLECTIONS.jobs,
      sortField,
      direction: f.direction === 'asc' ? 'asc' : 'desc',
      limit: f.limit,
      cursor: f.cursor,
      scanFields: SCAN_FIELDS,
      mapDoc: (s) => jobToApi(s),
    };
    const run = (where, covered) => pagedQuery({ ...base, where, memoryFilter: buildMemoryFilter(f, covered, now()) });
    return withIndexFallback(
      () => run(plan, planFields(plan)),
      () => run([], []),
    );
  }

  async function patch(id, fields) {
    const ref = jobs().doc(String(id));
    const snap = await ref.get();
    if (!snap.exists) throw notFound('Job not found');
    const update = { ...stripUndefined(fields), updatedAt: now() };
    await ref.set(update, { merge: true });
    return jobToApi(await ref.get(), { detail: true });
  }

  async function setStatus(id, status, { reason = null, source = 'manual' } = {}) {
    if (!JOB_STATUSES.includes(status)) throw invalid(`status must be one of ${JOB_STATUSES.join(', ')}`);
    return patch(id, { status, statusReason: reason, statusSource: source, statusChangedAt: now() });
  }

  async function setUserState(id, userState, applicationStage = null) {
    if (!USER_STATES.includes(userState)) throw invalid(`userState must be one of ${USER_STATES.join(', ')}`);
    return patch(id, { userState, applicationStage });
  }

  /** Deletes the job and its raw payloads; its keys stay, marked deleted, so scans don't resurrect it. */
  async function remove(id) {
    const database = getDb();
    return mutex.runExclusive(async () => {
      const ref = jobs().doc(String(id));
      const snap = await ref.get();
      if (!snap.exists) throw notFound('Job not found');
      const data = snap.data();
      const stamp = now();
      const raws = await ref.collection(RAW_SUBCOLLECTION).get();
      const bId = keyDocId(bucketKey(data));
      const bucketSnap = await keys().doc(bId).get();
      const bucket = bucketSnap.exists ? bucketSnap.data() : { jobIds: [], deletedFps: [] };

      const batch = database.batch();
      for (const s of data.sources || []) {
        batch.set(keys().doc(keyDocId(sourceKey(s.source, s.sourceJobId))), { type: 'source', jobId: snap.id, deleted: true, updatedAt: stamp }, { merge: true });
        const u = applyUrlKey(s.applyUrl);
        if (u) batch.set(keys().doc(keyDocId(urlKey(u))), { type: 'url', jobId: snap.id, deleted: true, updatedAt: stamp }, { merge: true });
      }
      batch.set(keys().doc(bId), {
        type: 'bucket',
        jobIds: (bucket.jobIds || []).filter((j) => j !== snap.id),
        deletedFps: [...new Set([...(bucket.deletedFps || []), data.fingerprint || snap.id])].slice(-50),
        updatedAt: stamp,
      });
      raws.docs.forEach((r) => batch.delete(r.ref));
      batch.delete(ref);
      await batch.commit();
      return { id: snap.id };
    });
  }

  // ----------------------------------------------------------- verification
  /**
   * Records the outcome of re-checking a job against each of its sources.
   * [checks] = [{ source, sourceJobId, found: true|false|null }].
   *
   * `found: null` (the source errored or can't tell) changes nothing — a
   * failing source never expires a job. A job is marked expired only when
   * EVERY source entry has reported "gone" on [expireAfter] consecutive checks.
   */
  async function recordVerification(id, checks, { expireAfter = 2 } = {}) {
    return mutex.runExclusive(async () => {
      const ref = jobs().doc(String(id));
      const snap = await ref.get();
      if (!snap.exists) throw notFound('Job not found');
      const data = snap.data();
      const stamp = now();
      let anyOpen = false;
      const sources = (data.sources || []).map((s) => {
        const c = checks.find((x) => x.source === s.source && String(x.sourceJobId) === String(s.sourceJobId));
        if (!c || c.found === null || c.found === undefined) return s;
        if (c.found) {
          anyOpen = true;
          return { ...s, missedChecks: 0, lastCheckedAt: stamp, lastSeenAt: stamp };
        }
        return { ...s, missedChecks: (s.missedChecks || 0) + 1, lastCheckedAt: stamp };
      });
      const update = { sources, updatedAt: stamp };
      if (anyOpen) update.lastVerifiedAt = stamp;
      const allGone = sources.length > 0 && sources.every((s) => (s.missedChecks || 0) >= expireAfter);
      if (allGone && data.status === 'active') {
        Object.assign(update, { status: 'expired', statusSource: 'verification', statusReason: 'no longer listed by any source', statusChangedAt: stamp });
      }
      await ref.set(stripUndefined(update), { merge: true });
      return { expired: Boolean(update.status === 'expired'), openSources: sources.filter((s) => !s.missedChecks).length };
    });
  }

  // ------------------------------------------------------------------ stats
  async function count(where = []) {
    const q = where.reduce((acc, [f, op, v]) => acc.where(f, op, v), jobs());
    return (await q.count().get()).data().count;
  }

  async function stats() {
    const since = new Date(now().getTime() - 24 * 3_600_000);
    const [total, active, expired, unseen, last24h, applied] = await Promise.all([
      count(),
      count([['status', '==', 'active']]),
      count([['status', '==', 'expired']]),
      count([['userState', '==', 'new']]),
      count([['discoveredAt', '>=', since]]),
      count([['userState', '==', 'applied']]),
    ]);
    return { total, active, expired, unseen, discoveredLast24h: last24h, applied };
  }

  return { upsertMany, get, getDetail, list, patch, setStatus, setUserState, remove, recordVerification, count, stats, companyKeyOf: companyKey };
}

export { toDate };
