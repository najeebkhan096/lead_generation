import {
  listExcelArchives,
  getExcelArchive,
  downloadExcelArchiveBuffer,
  deleteExcelArchive,
} from '../services/excelArchiveStore.js';
import { xlsxBufferToJson, sheetsToLeadsJson } from '../services/exportService.js';
import { resumeCategoryArchive } from '../services/multiCategoryOrchestrator.js';

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
 * Picks a stranded `status: 'partial'` archive (e.g. the backend crashed
 * or was restarted mid-scan) back up — see `resumeCategoryArchive` for the
 * actual logic. Responds the same shape/status as starting a fresh scan
 * (202 + started job info) since that's exactly what this does under the
 * hood; the frontend can point the existing live-scan dashboard at it.
 */
export async function resumeArchive(req, res) {
  try {
    const { concurrency } = req.body || {};
    const result = await resumeCategoryArchive({
      archiveId: req.params.id,
      concurrency: concurrency != null ? Number(concurrency) : undefined,
    });
    return res.status(202).json({ started: true, ...result });
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
