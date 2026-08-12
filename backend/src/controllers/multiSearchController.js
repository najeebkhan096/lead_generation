import {
  startMultiCategorySearch,
  getMultiJobSnapshot,
  cancelMultiJob,
  cancelCategory,
  pauseMultiJob,
  resumeMultiJob,
  pauseCategory,
  resumeCategory,
} from '../services/multiCategoryOrchestrator.js';
import { countryMeta } from '../data/countries.js';

/**
 * Starts a concurrent multi-category search in the background and returns
 * immediately (202) — same "poll for status" shape as the existing
 * /api/search endpoint, for the same reason (Render's free tier kills long
 * HTTP requests).
 */
export async function startMultiSearch(req, res) {
  const {
    categories,
    countries,
    concurrency = 4,
    dateRange = '30',
    maxResultsPerState = 150,
    targetLeadCount = 100,
    analyze = false,
    exportOnly = false,
    country = 'US',
  } = req.body || {};

  if (!Array.isArray(categories) || !categories.length) {
    return res.status(400).json({ error: 'categories array is required' });
  }

  try {
    const result = await startMultiCategorySearch({
      categories,
      countries: Array.isArray(countries) && countries.length ? countries.map(String) : undefined,
      concurrency: Number(concurrency),
      dateRange: String(dateRange),
      maxResultsPerState: Number(maxResultsPerState) || 150,
      targetLeadCount: Number(targetLeadCount) || 100,
      analyze: Boolean(analyze),
      exportOnly: Boolean(exportOnly),
      country: String(country),
    });

    const scopeDesc = result.countries.length > 1
      ? `${result.categories.length} categor${result.categories.length === 1 ? 'y' : 'ies'} × ${result.countries.map((c) => countryMeta(c).shortName).join(', ')}`
      : `${result.categories.length} categories, ${countryMeta(result.countries[0]).label}`;

    return res.status(202).json({
      started: true,
      ...result,
      message: `Multi-category search started: ${scopeDesc}, ${result.concurrency} workers.`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start multi-category search' });
  }
}

export function getMultiStatus(_req, res) {
  const snapshot = getMultiJobSnapshot();
  if (!snapshot) {
    return res.json({ active: false, status: 'idle' });
  }
  return res.json(snapshot);
}

export function cancelJob(_req, res) {
  const ok = cancelMultiJob();
  return res.json({ success: ok });
}

export function cancelOneCategory(req, res) {
  const { category, country } = req.body || {};
  if (!category) return res.status(400).json({ error: 'category is required' });
  const ok = cancelCategory(String(category), country ? String(country) : undefined);
  return res.json({ success: ok });
}

export function pauseJob(_req, res) {
  const ok = pauseMultiJob();
  return res.json({ success: ok });
}

export function resumeJob(_req, res) {
  const ok = resumeMultiJob();
  return res.json({ success: ok });
}

export function pauseOneCategory(req, res) {
  const { category, country } = req.body || {};
  if (!category) return res.status(400).json({ error: 'category is required' });
  const ok = pauseCategory(String(category), country ? String(country) : undefined);
  return res.json({ success: ok });
}

export function resumeOneCategory(req, res) {
  const { category, country } = req.body || {};
  if (!category) return res.status(400).json({ error: 'category is required' });
  const ok = resumeCategory(String(category), country ? String(country) : undefined);
  return res.json({ success: ok });
}
