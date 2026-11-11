import { isCoverageTier, describeCoverage, COVERAGE_TIERS } from '../../data/usCoverage.js';
import { perMinuteFromEnv } from '../../scraper/rateLimit.js';
import {
  startStateCityScan,
  getStateCityJobSnapshot,
  cancelStateCityJob,
  pauseStateCityJob,
  resumeStateCityJob,
  resumeNoWebsiteScan,
  getStateCityJobSnapshot as currentScan,
} from './stateCityOrchestrator.js';
import { listResumableRuns, deleteRun } from './noWebsiteRunStore.js';
import { getFirebaseStatus } from '../../firebase/admin.js';

export async function startScan(req, res) {
  const { categories, concurrency = 8, dateRange = '30', maxResultsPerCity = 160, analyze = false, allowUnsignedScan = false, coverage = 'standard', mode = 'reviews' } = req.body || {};

  if (!Array.isArray(categories) || !categories.length) {
    return res.status(400).json({ error: 'categories array is required' });
  }

  if (!isCoverageTier(coverage)) {
    return res.status(400).json({ error: 'coverage must be standard, extended or maximum' });
  }

  if (mode !== 'reviews' && mode !== 'no_website') {
    return res.status(400).json({ error: 'mode must be reviews or no_website' });
  }

  try {
    const result = await startStateCityScan({
      mode,
      categories,
      concurrency: Number(concurrency),
      dateRange: String(dateRange),
      maxResultsPerCity: Number(maxResultsPerCity) || 160,
      analyze: Boolean(analyze),
      coverage,
      // Only for emergencies: scanning without a Google session misses reviews.
      requireSignIn: allowUnsignedScan !== true,
    });

    return res.status(202).json({
      started: true,
      ...result,
      message: `${mode === 'no_website' ? 'No-website scan' : 'Scan'} started: ${result.categories.length} categories × ${result.totalStates} states, ${result.concurrency} workers.`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start scan', code: err.code });
  }
}

export function getStatus(_req, res) {
  const snapshot = getStateCityJobSnapshot();
  if (!snapshot) {
    return res.json({ active: false, status: 'idle' });
  }
  return res.json(snapshot);
}

export function cancelScan(_req, res) {
  const ok = cancelStateCityJob();
  return res.json({ success: ok });
}

export function pauseScan(_req, res) {
  const ok = pauseStateCityJob();
  return res.json({ success: ok });
}

export function resumeScan(_req, res) {
  const ok = resumeStateCityJob();
  return res.json({ success: ok });
}

/** GET /api/state-scan/coverage: the coverage tiers, with their rough size and time. */
export function getCoverage(_req, res) {
  const perMinute = perMinuteFromEnv();
  return res.json({
    perMinute,
    tiers: Object.keys(COVERAGE_TIERS).map((tier) => describeCoverage(tier, perMinute)),
  });
}

/** GET /api/state-scan/runs: no-website scans that were stopped or cut off and can be resumed. */
export async function listRuns(_req, res) {
  // Progress is kept in Firestore; without it there is nothing to resume.
  if (!getFirebaseStatus().configured) return res.json({ runs: [] });
  try {
    return res.json({ runs: await listResumableRuns() });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Failed to list scans' });
  }
}

/** POST /api/state-scan/runs/:id/resume */
export async function resumeRun(req, res) {
  try {
    const concurrency = req.body?.concurrency == null ? undefined : Number(req.body.concurrency);
    const result = await resumeNoWebsiteScan({ runId: req.params.id, concurrency });
    return res.status(202).json({ started: true, ...result, message: `Resumed: ${result.remaining} cities left.` });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to resume the scan', code: err.code });
  }
}

/** DELETE /api/state-scan/runs/:id: forget a stopped scan's saved progress. */
export async function discardRun(req, res) {
  try {
    const live = currentScan();
    if (live && live.status === 'running' && live.runId === req.params.id) {
      return res.status(409).json({ error: 'This scan is running. Stop it first.' });
    }
    const removed = await deleteRun(req.params.id);
    return removed ? res.json({ success: true }) : res.status(404).json({ error: 'Scan not found' });
  } catch (err) {
    return res.status(500).json({ error: err.message || 'Failed to discard the scan' });
  }
}
