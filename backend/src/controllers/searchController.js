import { findLeads, getCurrentLeads } from '../services/leadService.js';
import { analyzeReview, generateOutreachMessage } from '../services/reviewAnalyzer.js';
import { clearLeads, setStatus, getStore } from '../utils/memoryStore.js';

/**
 * Start search in the background and return immediately (202).
 * Render free tier kills long HTTP requests (~100s) with 502 —
 * clients must poll GET /api/search/status then GET /api/search/results.
 */
export async function startSearch(req, res) {
  const {
    location,
    category,
    dateRange = '30',
    maxResults = 8,
    analyze = false,
  } = req.body || {};

  if (!location || !category) {
    return res.status(400).json({
      error: 'location and category are required',
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

  // Do not await — respond before Render gateway times out
  findLeads({
    location: String(location).trim(),
    category: String(category).trim(),
    dateRange: String(dateRange),
    maxResults: Number(maxResults) || 8,
    analyze: Boolean(analyze),
  }).catch((err) => {
    console.error('Background search failed:', err);
    setStatus('error', err.message || 'Search failed');
  });

  return res.status(202).json({
    started: true,
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
