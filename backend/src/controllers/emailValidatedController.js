import {
  listEmailVerifiedArchives,
  getEmailVerifiedArchive,
  downloadEmailVerifiedArchiveBuffer,
  deleteEmailVerifiedArchive,
  uploadEmailVerifiedArchive,
  buildEmailVerifiedFileName,
} from '../services/emailValidatedStore.js';
import { leadsToXlsxBuffer, xlsxBufferToJson, sheetsToLeadsJson } from '../services/exportService.js';

/**
 * Body: `{ sheets: [{ name, leads }], sourceArchiveId?, sourceFileName?, countries? }`
 * — same contract as the WhatsApp validated archive upload, except each lead
 * also carries its verified `email` / `emailSource`, written to extra
 * workbook columns.
 */
export async function uploadEmailVerified(req, res) {
  const { sheets, sourceArchiveId, sourceFileName, countries } = req.body || {};
  if (!Array.isArray(sheets) || !sheets.length) {
    return res.status(400).json({ error: 'sheets array is required' });
  }
  const nonEmpty = sheets.filter((s) => Array.isArray(s.leads) && s.leads.length);
  if (!nonEmpty.length) {
    return res.status(400).json({ error: 'No email-verified businesses to upload' });
  }
  try {
    const categories = nonEmpty.map((s) => s.name);
    const totalLeads = nonEmpty.reduce((sum, s) => sum + s.leads.length, 0);
    const buffer = await leadsToXlsxBuffer(nonEmpty, { withEmail: true });
    const fileName = buildEmailVerifiedFileName({ categories });
    const record = await uploadEmailVerifiedArchive({
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
    return res.status(err.status || 500).json({ error: err.message || 'Failed to upload email-verified businesses' });
  }
}

export async function listEmailVerified(_req, res) {
  try {
    return res.json({ archives: await listEmailVerifiedArchives() });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load email-verified archives' });
  }
}

export async function getEmailVerifiedData(req, res) {
  try {
    const found = await downloadEmailVerifiedArchiveBuffer(req.params.id);
    if (!found) return res.status(404).json({ error: 'Archive not found' });
    const sheets = await xlsxBufferToJson(found.buffer);
    return res.json({ archive: found.record, sheets });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to read archive data' });
  }
}

export async function getEmailVerifiedLeads(req, res) {
  try {
    const found = await downloadEmailVerifiedArchiveBuffer(req.params.id);
    if (!found) return res.status(404).json({ error: 'Archive not found' });
    const sheets = await xlsxBufferToJson(found.buffer);
    const leads = sheetsToLeadsJson(sheets, `email-verified-${req.params.id}`);
    return res.json({ archive: found.record, leads });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to extract leads from archive' });
  }
}

export async function downloadEmailVerified(req, res) {
  try {
    const archive = await getEmailVerifiedArchive(req.params.id);
    if (!archive) return res.status(404).json({ error: 'Archive not found' });
    return res.redirect(archive.downloadUrl);
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to download archive' });
  }
}

export async function removeEmailVerified(req, res) {
  try {
    const ok = await deleteEmailVerifiedArchive(req.params.id);
    if (!ok) return res.status(404).json({ error: 'Archive not found' });
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to delete archive' });
  }
}
