import { findLeads, findLeadsNationwide, getCurrentLeads } from '../services/leadService.js';
import { analyzeReview, generateOutreachMessage } from '../services/reviewAnalyzer.js';
import { clearLeads, setStatus, getStore } from '../utils/memoryStore.js';

function isNationwideRequest(body = {}) {
  if (body.nationwide === true || body.nationwide === 'true') return true;
  const loc = String(body.location || '').trim().toLowerCase();
  if (!loc) return true; // no location → search all US states
  return (
    loc === 'usa' ||
    loc === 'us' ||
    loc === 'united states' ||
    loc === 'all' ||
    loc === 'all us states' ||
    loc === 'all usa' ||
    loc === 'nationwide'
  );
}

/**
 * Start search in the background and return immediately (202).
 * Render free tier kills long HTTP requests (~100s) with 502 —
 * clients must poll GET /api/search/status then GET /api/search/results.
 *
 * Nationwide (default): loops all US states until ~100 WhatsApp 1★ leads.
 */
export async function startSearch(req, res) {
  const {
    location,
    category,
    dateRange = '30',
    maxResults = 16,
    maxResultsPerState,
    targetLeadCount = 100,
    analyze = false,
    nationwide,
  } = req.body || {};

  if (!category) {
    return res.status(400).json({
      error: 'category is required',
    });
  }

  const store = getStore();
  if (store.status === 'searching') {
    return res.status(409).json({
      error: 'A search is already running. Poll /api/search/status.',
      status: store.status,
      progress: store.progress,
    });
  }

  setStatus('searching');

  const runNationwide = isNationwideRequest({ location, nationwide });

  if (runNationwide) {
    findLeadsNationwide({
      category: String(category).trim(),
      dateRange: String(dateRange),
      maxResultsPerState: Number(maxResultsPerState || maxResults) || 16,
      targetLeadCount: Number(targetLeadCount) || 100,
      analyze: Boolean(analyze),
    }).catch((err) => {
      console.error('Background nationwide search failed:', err);
      setStatus('error', err.message || 'Search failed');
    });

    return res.status(202).json({
      started: true,
      nationwide: true,
      targetLeadCount: Number(targetLeadCount) || 100,
      message:
        'Nationwide US search started (all states). Poll /api/search/status until status is done or error.',
    });
  }

  if (!location) {
    return res.status(400).json({
      error: 'location is required when nationwide is false',
    });
  }

  findLeads({
    location: String(location).trim(),
    category: String(category).trim(),
    dateRange: String(dateRange),
    maxResults: Number(maxResults) || 16,
    analyze: Boolean(analyze),
  }).catch((err) => {
    console.error('Background search failed:', err);
    setStatus('error', err.message || 'Search failed');
  });

  return res.status(202).json({
    started: true,
    nationwide: false,
    message: 'Search started. Poll /api/search/status until status is done or error.',
  });
}

export function getStatus(_req, res) {
  const store = getCurrentLeads();
  return res.json({
    status: store.status,
    error: store.error,
    progress: store.progress,
    lastSearch: store.lastSearch,
    leadCount: store.leads.length,
  });
}

export function getResults(_req, res) {
  const store = getCurrentLeads();
  return res.json({
    status: store.status,
    lastSearch: store.lastSearch,
    leads: store.leads,
  });
}

export function clearResults(_req, res) {
  clearLeads();
  return res.json({ success: true, message: 'In-memory leads cleared' });
}

export function analyze(req, res) {
  const { reviewText, businessName } = req.body || {};
  if (!reviewText) {
    return res.status(400).json({ error: 'reviewText is required' });
  }
  const result = analyzeReview(reviewText, businessName);
  return res.json(result);
}

export function outreach(req, res) {
  const { businessName, category } = req.body || {};
  return res.json({
    message: generateOutreachMessage(businessName, category),
  });
}
