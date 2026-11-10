/**
 * The Jobs overview numbers: jobs, companies, applications, last scan and how
 * scans have been going. Counts are Firestore aggregations (no documents
 * read); the result is cached briefly because the overview page polls.
 */

import { serialize } from './firestoreUtil.js';

const TTL_MS = 15_000;

export function createStatsService({ jobStore, companyStore, applicationStore, runStore, registry, now = () => Date.now() } = {}) {
  let cached = null;

  async function compute() {
    const [jobs, companies, applications, byStage, runs] = await Promise.all([
      jobStore.stats(),
      companyStore.count(),
      applicationStore.count(),
      applicationStore.countsByStage(),
      runStore.recent(30),
    ]);
    const finished = runs.filter((r) => ['completed', 'failed', 'stopped'].includes(r.status));
    const last = runs[0] || null;
    const counts = { completed: 0, failed: 0, stopped: 0 };
    for (const r of finished) counts[r.status] += 1;

    // Per source, over those runs: how often it answered and how often it failed.
    const sources = {};
    for (const r of runs) {
      for (const [id, s] of Object.entries(r.sources || {})) {
        const agg = (sources[id] ||= { requests: 0, found: 0, errors: 0, runs: 0 });
        agg.requests += s.requests || 0;
        agg.found += s.found || 0;
        agg.errors += s.errors || 0;
        agg.runs += 1;
      }
    }

    return serialize({
      jobs,
      companies,
      applications: { total: applications, byStage },
      lastScan: last && { id: last.id, searchName: last.searchName, status: last.status, startedAt: last.startedAt, finishedAt: last.finishedAt, totals: last.totals, jobs: last.jobs },
      scans: { recent: runs.length, ...counts, successRate: finished.length ? Math.round((counts.completed / finished.length) * 100) : null },
      sources,
      generatedAt: new Date(now()),
    });
  }

  return {
    async overview({ force = false } = {}) {
      if (!force && cached && now() - cached.at < TTL_MS) return cached.value;
      const value = await compute();
      cached = { at: now(), value };
      return value;
    },
    invalidate() {
      cached = null;
    },
    registryHealth: () => registry?.describeAll?.().map((s) => ({ id: s.id, name: s.name, configured: s.configured, enabled: s.enabled, status: s.status })) ?? [],
  };
}
