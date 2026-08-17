import {
  listExcelArchives,
  getExcelArchive,
  downloadExcelArchiveBuffer,
  deleteExcelArchive,
} from '../services/excelArchiveStore.js';
import { xlsxBufferToJson, sheetsToLeadsJson } from '../services/exportService.js';
import { resumeCategoryArchive } from '../services/multiCategoryOrchestrator.js';
import { resumeStateCityScan } from '../services/stateCityOrchestrator.js';
import { US_STATE_CITIES } from '../data/usStateCities.js';

const US_STATE_NAMES = new Set(US_STATE_CITIES.map((s) => s.state));

export async function listArchives(_req, res) {
  try {
    const archives = await listExcelArchives();
    return res.json({ archives });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load Excel archives' });
  }
}

export async function getArchive(req, res) {
  try {
    const archive = await getExcelArchive(req.params.id);
    if (!archive) return res.status(404).json({ error: 'Archive not found' });
    return res.json({ archive });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load archive' });
  }
}

/**
 * Converts an archive's rows into the same JSON shape `/api/search/results`
 * and `/api/db/leads` return, so the frontend can render them with the
 * exact same `LeadCard` widget it already uses everywhere else — these
 * leads were never saved to Firestore (that's the whole point of
 * `exportOnly` scans), so `dbId` is always null and actions that require a
 * saved doc (WhatsApp status edits, delete) don't apply here.
 */
export async function getArchiveLeads(req, res) {
  try {
    const found = await downloadExcelArchiveBuffer(req.params.id);
    if (!found) return res.status(404).json({ error: 'Archive not found' });
    const sheets = await xlsxBufferToJson(found.buffer);
    const leads = sheetsToLeadsJson(sheets, `archive-${req.params.id}`);
    return res.json({ archive: found.record, leads });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to extract leads from archive' });
  }
}

export async function getArchiveData(req, res) {
  try {
    const found = await downloadExcelArchiveBuffer(req.params.id);
    if (!found) return res.status(404).json({ error: 'Archive not found' });
    const sheets = await xlsxBufferToJson(found.buffer);
    return res.json({ archive: found.record, sheets });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to read archive data' });
  }
}

export async function downloadArchive(req, res) {
  try {
    const archive = await getExcelArchive(req.params.id);
    if (!archive) return res.status(404).json({ error: 'Archive not found' });
    return res.redirect(archive.downloadUrl);
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to download archive' });
  }
}

/**
 * Picks a stranded `status: 'partial'` archive (e.g. the backend crashed,
 * restarted, or the scan was cancelled mid-way) back up. Two archive
 * "shapes" exist depending on which engine produced it — the current
 * state-by-state scan (`resumeStateCityScan`) and the older, dormant
 * per-country one (`resumeCategoryArchive`), kept around for archives that
 * predate the current engine. Neither stores which engine made it, so this
 * infers it from the data itself: only the state/city engine's
 * `completedCountries` list can ever contain real US state names (the
 * older engine only ever put country codes/names there) — a reliable,
 * self-describing signal rather than a stored flag that could drift.
 * Responds the same shape/status as starting a fresh scan (202 + started
 * job info); `engine` tells the frontend which live dashboard to open.
 */
export async function resumeArchive(req, res) {
  try {
    const archive = await getExcelArchive(req.params.id);
    if (!archive) return res.status(404).json({ error: 'Archive not found' });

    const isStateCity = (archive.completedCountries || []).some((name) => US_STATE_NAMES.has(name));
    const { concurrency } = req.body || {};
    const opts = {
      archiveId: req.params.id,
      concurrency: concurrency != null ? Number(concurrency) : undefined,
    };
    const result = isStateCity ? await resumeStateCityScan(opts) : await resumeCategoryArchive(opts);
    return res.status(202).json({ started: true, engine: isStateCity ? 'state-city' : 'multi-country', ...result });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to resume archive' });
  }
}

export async function removeArchive(req, res) {
  try {
    const ok = await deleteExcelArchive(req.params.id);
    if (!ok) return res.status(404).json({ error: 'Archive not found' });
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to delete archive' });
  }
}
