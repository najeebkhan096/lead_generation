import {
  listValidatedArchives,
  getValidatedArchive,
  downloadValidatedArchiveBuffer,
  deleteValidatedArchive,
  uploadValidatedArchive,
  buildValidatedFileName,
} from '../services/whatsappValidatedStore.js';
import { leadsToXlsxBuffer, xlsxBufferToJson, sheetsToLeadsJson } from '../services/exportService.js';

/**
 * Body: `{ sheets: [{ name, leads }], sourceArchiveId?, sourceFileName?, countries? }`
 * — `leads` per sheet must already be in the standard lead JSON shape (the
 * frontend builds these from validated `Lead`s it already holds in memory,
 * same shape `/api/search/results` and the Excel Archive `/leads` endpoint
 * return). One sheet per category, matching how the source Excel scan was
 * organized.
 */
export async function uploadValidated(req, res) {
  const { sheets, sourceArchiveId, sourceFileName, countries } = req.body || {};
  if (!Array.isArray(sheets) || !sheets.length) {
    return res.status(400).json({ error: 'sheets array is required' });
  }
  const nonEmpty = sheets.filter((s) => Array.isArray(s.leads) && s.leads.length);
  if (!nonEmpty.length) {
    return res.status(400).json({ error: 'No validated businesses to upload' });
  }
  try {
    const categories = nonEmpty.map((s) => s.name);
    const totalLeads = nonEmpty.reduce((sum, s) => sum + s.leads.length, 0);
    const buffer = await leadsToXlsxBuffer(nonEmpty);
    const fileName = buildValidatedFileName({ categories });
    const record = await uploadValidatedArchive({
      buffer,
      fileName,
      categories,
      countries: Array.isArray(countries) ? countries : [],
      totalLeads,
      sourceArchiveId,
      sourceFileName,
    });
    return res.json({ archive: record });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to upload validated businesses' });
  }
}

export async function listValidated(_req, res) {
  try {
    const archives = await listValidatedArchives();
    return res.json({ archives });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load validated archives' });
  }
}

export async function getValidatedData(req, res) {
  try {
    const found = await downloadValidatedArchiveBuffer(req.params.id);
    if (!found) return res.status(404).json({ error: 'Archive not found' });
    const sheets = await xlsxBufferToJson(found.buffer);
    return res.json({ archive: found.record, sheets });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to read archive data' });
  }
}

export async function getValidatedLeads(req, res) {
  try {
    const found = await downloadValidatedArchiveBuffer(req.params.id);
    if (!found) return res.status(404).json({ error: 'Archive not found' });
    const sheets = await xlsxBufferToJson(found.buffer);
    const leads = sheetsToLeadsJson(sheets, `wa-verified-${req.params.id}`);
    return res.json({ archive: found.record, leads });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to extract leads from archive' });
  }
}

export async function downloadValidated(req, res) {
  try {
    const archive = await getValidatedArchive(req.params.id);
    if (!archive) return res.status(404).json({ error: 'Archive not found' });
    return res.redirect(archive.downloadUrl);
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to download archive' });
  }
}

export async function removeValidated(req, res) {
  try {
    const ok = await deleteValidatedArchive(req.params.id);
    if (!ok) return res.status(404).json({ error: 'Archive not found' });
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to delete archive' });
  }
}
