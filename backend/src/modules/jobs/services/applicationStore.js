/**
 * `job_applications` — the application tracker. One document per job (the id
 * is the job id): where the application stands, notes and follow-up date.
 *
 * Saved → Applied → Assessment → Interview → Offered, or Rejected / Withdrawn.
 * The job document keeps a coarse `userState` and the `applicationStage` so
 * the Jobs Explorer can filter ("Saved", "Applied") without a join.
 */

import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS, APPLICATION_STAGES, userStateForStage } from '../models/constants.js';
import { notFound, conflict } from '../utils/errors.js';
import { serialize, stripUndefined } from './firestoreUtil.js';
import { pagedQuery } from './paging.js';

export function createApplicationStore({ db = null, jobStore, now = () => new Date() } = {}) {
  const database = () => db || getFirestore();
  const col = () => database().collection(COLLECTIONS.applications);
  const api = (snap) => serialize({ id: snap.id, ...snap.data() });

  /** The snapshot of the job kept on the application so the tracker lists without a join. */
  const jobSummary = (job) => ({
    title: job.title,
    companyName: job.companyName,
    locationText: job.locationText ?? [job.city, job.state, job.country].filter(Boolean).join(', '),
    sourceUrl: job.sourceUrl ?? null,
    applyUrl: job.applyUrl ?? null,
  });

  return {
    /**
     * Creates or updates the application for a job. Moving to a stage also
     * records when (`history`) and keeps the job's userState in step.
     */
    async upsert(jobId, fields) {
      const jobSnap = await jobStore.get(jobId);
      if (!jobSnap) throw notFound('Job not found');
      const ref = col().doc(String(jobId));
      const prev = await ref.get();
      const stamp = now();
      const prevData = prev.exists ? prev.data() : null;
      const stage = fields.stage ?? prevData?.stage ?? 'saved';
      if (!APPLICATION_STAGES.includes(stage)) throw conflict(`Unknown stage "${stage}"`);

      const stageChanged = !prevData || prevData.stage !== stage;
      const doc = {
        ...(prevData || { createdAt: stamp, history: [] }),
        jobId: jobSnap.id,
        job: jobSummary(jobSnap.data()),
        stage,
        notes: fields.notes ?? prevData?.notes ?? '',
        contact: fields.contact ?? prevData?.contact ?? null,
        appliedAt: fields.appliedAt !== undefined ? fields.appliedAt : prevData?.appliedAt ?? (stage === 'applied' ? stamp : null),
        followUpAt: fields.followUpAt !== undefined ? fields.followUpAt : prevData?.followUpAt ?? null,
        updatedAt: stamp,
        stageChangedAt: stageChanged ? stamp : prevData?.stageChangedAt ?? stamp,
      };
      if (stageChanged) doc.history = [...(prevData?.history || []), { stage, at: stamp }].slice(-30);
      await ref.set(stripUndefined(doc));
      await jobStore.setUserState(jobSnap.id, userStateForStage(stage), stage);
      return api(await ref.get());
    },

    async get(jobId) {
      const snap = await col().doc(String(jobId)).get();
      if (!snap.exists) throw notFound('No application tracked for this job');
      return api(snap);
    },

    async remove(jobId) {
      const ref = col().doc(String(jobId));
      const snap = await ref.get();
      if (!snap.exists) throw notFound('No application tracked for this job');
      await ref.delete();
      // The job goes back to untriaged — unless it vanished meanwhile.
      if (await jobStore.get(jobId)) await jobStore.setUserState(jobId, 'new', null);
      return { id: snap.id };
    },

    async list({ stage, limit, cursor } = {}) {
      return pagedQuery({
        db: database(),
        collection: COLLECTIONS.applications,
        where: stage ? [['stage', '==', stage]] : [],
        sortField: 'updatedAt',
        limit,
        cursor,
        mapDoc: api,
      });
    },

    /** Applications per stage — the pipeline's column counts. */
    async countsByStage() {
      const counts = await Promise.all(APPLICATION_STAGES.map(async (s) => [s, (await col().where('stage', '==', s).count().get()).data().count]));
      return Object.fromEntries(counts);
    },

    async count() {
      return (await col().count().get()).data().count;
    },
  };
}
