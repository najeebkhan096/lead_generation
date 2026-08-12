import {
  addWatchlistEntry,
  listWatchlistEntries,
  deleteWatchlistEntry,
  assignWatchlistEntry,
} from '../services/watchlistStore.js';
import { scanWatchlist } from '../services/watchlistScanner.js';

let scanning = false;

export async function addEntry(req, res) {
  const { url, name, country, assignedTo, assignedToName } = req.body || {};
  if (!url || typeof url !== 'string' || !/^https?:\/\//i.test(url.trim())) {
    return res.status(400).json({ error: 'A valid Google Maps business URL is required' });
  }
  try {
    const entry = await addWatchlistEntry({
      url: url.trim(),
      name: name?.trim(),
      country: country || 'US',
      assignedTo: assignedTo || null,
      assignedToName: assignedToName?.trim() || null,
    });
    return res.json({ entry });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to add business' });
  }
}

export async function assignEntry(req, res) {
  const { assignedTo, assignedToName } = req.body || {};
  try {
    const entry = await assignWatchlistEntry(req.params.id, {
      assignedTo: assignedTo || null,
      assignedToName: assignedToName?.trim() || null,
    });
    return res.json({ entry });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to assign business' });
  }
}

export async function listEntries(_req, res) {
  try {
    const entries = await listWatchlistEntries();
    return res.json({ entries });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load watchlist' });
  }
}

export async function removeEntry(req, res) {
  try {
    await deleteWatchlistEntry(req.params.id);
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to remove business' });
  }
}

export async function triggerScan(req, res) {
  if (scanning) {
    return res.status(409).json({ error: 'A watchlist scan is already running' });
  }
  scanning = true;
  try {
    const { dateRange } = req.body || {};
    const results = await scanWatchlist({ dateRange: dateRange ? String(dateRange) : '30' });
    return res.json({ results, scannedAt: new Date().toISOString() });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Watchlist scan failed' });
  } finally {
    scanning = false;
  }
}
