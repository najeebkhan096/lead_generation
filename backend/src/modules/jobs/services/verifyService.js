/**
 * Re-checking that postings are still open.
 *
 * For each source a job was found on, the adapter is asked to re-read the
 * posting. Only a DEFINITIVE answer counts: `found: false` (the source says
 * 404/410, or a board that was read in full no longer lists it). An error, a
 * timeout, a bot wall or an adapter that can't tell is `found: null` and
 * changes nothing — a failing source never expires a job. A job expires only
 * when every source reported it gone on consecutive checks (jobStore).
 */

import { silentLogger } from '../utils/logger.js';
import { notFound } from '../utils/errors.js';
import { describeError } from '../utils/errors.js';

export function createVerifyService({ jobStore, registry, log = silentLogger, expireAfter = 2 } = {}) {
  async function verifyJob(id) {
    const snap = await jobStore.get(id);
    if (!snap) throw notFound('Job not found');
    const job = snap.data();
    await registry.load();

    const checks = [];
    const details = [];
    for (const entry of job.sources || []) {
      let found = null;
      let error = null;
      try {
        if (registry.has?.(entry.source) !== false) {
          const adapter = registry.adapter(entry.source);
          const r = await adapter.getJobDetails({ sourceJobId: entry.sourceJobId, sourceRef: entry.sourceRef, sourceUrl: entry.sourceUrl });
          found = r.found ?? null;
          if (r.found && r.job) await jobStore.upsertMany([r.job], { runId: null });
        }
      } catch (err) {
        error = describeError(err);
        log.warn('verification could not reach a source', { jobId: id, source: entry.source, error: err });
      }
      checks.push({ source: entry.source, sourceJobId: entry.sourceJobId, found });
      details.push({ source: entry.source, found, error });
    }
    const outcome = await jobStore.recordVerification(id, checks, { expireAfter });
    return { id, ...outcome, sources: details };
  }

  /** Re-checks up to [limit] active jobs, least recently verified first. */
  async function verifyStale({ limit = 20, olderThanDays = 3 } = {}) {
    const cutoff = new Date(Date.now() - olderThanDays * 86_400_000);
    const page = await jobStore.list({ status: 'active', sort: 'updated', direction: 'asc', limit: Math.min(limit, 100) });
    const stale = page.items.filter((j) => new Date(j.lastVerifiedAt) < cutoff);
    const results = [];
    for (const j of stale) results.push(await verifyJob(j.id).catch((err) => ({ id: j.id, error: describeError(err) })));
    return { checked: results.length, expired: results.filter((r) => r.expired).length, results };
  }

  return { verifyJob, verifyStale };
}
