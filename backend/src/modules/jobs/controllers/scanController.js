/** Starting, controlling and inspecting scans. */

import { q } from '../validators/validate.js';

export function createScanController({ engine, runStore, queueStore, statsService }) {
  return {
    async start(req, res) {
      const run = await engine.start(req.params.id, { trigger: 'manual' });
      statsService.invalidate();
      res.status(202).json({ run });
    },

    async progress(req, res) {
      res.json({ run: await engine.progress(req.params.runId) });
    },

    async pause(req, res) {
      res.json({ run: await engine.pause(req.params.runId) });
    },

    async resume(req, res) {
      res.json({ run: await engine.resume(req.params.runId) });
    },

    async stop(req, res) {
      const run = await engine.stop(req.params.runId);
      statsService.invalidate();
      res.json({ run });
    },

    /** Scan history, newest first. */
    async history(req, res) {
      res.json(await runStore.list({ limit: q.int(req.query, 'limit'), cursor: q.str(req.query, 'cursor'), searchId: q.str(req.query, 'searchId') }));
    },

    /** Runs still working (live numbers for those in this process). */
    async active(_req, res) {
      const runs = await runStore.listActive();
      const live = await Promise.all(runs.map((r) => engine.progress(r.id).catch(() => null)));
      res.json({ runs: live.filter(Boolean) });
    },

    /** The combinations that failed, with the reason — "source-level errors" in detail. */
    async failures(req, res) {
      const tasks = await queueStore.failedSample(req.params.runId, q.int(req.query, 'limit') ?? 50);
      res.json({
        failures: tasks.map((t) => ({ id: t.id, country: t.country, state: t.state, city: t.city, title: t.title, attempts: t.attempts, error: t.error, sources: t.result?.sources ?? null })),
      });
    },
  };
}
