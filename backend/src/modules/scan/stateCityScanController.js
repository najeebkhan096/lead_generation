import { isCoverageTier, describeCoverage, COVERAGE_TIERS } from '../../data/usCoverage.js';
import { perMinuteFromEnv } from '../../scraper/rateLimit.js';
import {
  startStateCityScan,
  getStateCityJobSnapshot,
  cancelStateCityJob,
  pauseStateCityJob,
  resumeStateCityJob,
} from './stateCityOrchestrator.js';

export async function startScan(req, res) {
  const { categories, concurrency = 8, dateRange = '30', maxResultsPerCity = 160, analyze = false, allowUnsignedScan = false, coverage = 'standard' } = req.body || {};

  if (!Array.isArray(categories) || !categories.length) {
    return res.status(400).json({ error: 'categories array is required' });
  }

  if (!isCoverageTier(coverage)) {
    return res.status(400).json({ error: 'coverage must be standard, extended or maximum' });
  }

  try {
    const result = await startStateCityScan({
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
      message: `Scan started: ${result.categories.length} categories × ${result.totalStates} states, ${result.concurrency} workers.`,
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
