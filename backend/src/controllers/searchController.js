import { findLeads, getCurrentLeads } from '../services/leadService.js';
import { analyzeReview, generateOutreachMessage } from '../services/reviewAnalyzer.js';
import { clearLeads } from '../utils/memoryStore.js';

export async function startSearch(req, res) {
  const {
    location,
    category,
    dateRange = '30',
    maxResults = 12,
    analyze = false,
  } = req.body || {};

  if (!location || !category) {
    return res.status(400).json({
      error: 'location and category are required',
    });
  }

  // Run async so client can poll /api/search/status
  // But for MVP simplicity, also await and return results.
  try {
    const result = await findLeads({
      location: String(location).trim(),
      category: String(category).trim(),
      dateRange: String(dateRange),
      maxResults: Number(maxResults) || 12,
      analyze: Boolean(analyze),
    });

    return res.json({
      success: true,
      ...result,
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      error: err.message || 'Search failed',
    });
  }
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
