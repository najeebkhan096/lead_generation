import {
  startStateCityScan,
  getStateCityJobSnapshot,
  cancelStateCityJob,
  pauseStateCityJob,
  resumeStateCityJob,
} from '../services/stateCityOrchestrator.js';

export async function startScan(req, res) {
  const { categories, concurrency = 4, dateRange = '30', maxResultsPerCity = 160, analyze = false } = req.body || {};

  if (!Array.isArray(categories) || !categories.length) {
    return res.status(400).json({ error: 'categories array is required' });
  }

  try {
    const result = await startStateCityScan({
      categories,
      concurrency: Number(concurrency),
      dateRange: String(dateRange),
      maxResultsPerCity: Number(maxResultsPerCity) || 160,
      analyze: Boolean(analyze),
    });

    return res.status(202).json({
      started: true,
      ...result,
      message: `Scan started: ${result.categories.length} categories × ${result.totalStates} states, ${result.concurrency} workers.`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start scan' });
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
