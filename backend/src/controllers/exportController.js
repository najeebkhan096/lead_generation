import { getCurrentLeads } from '../services/leadService.js';
import { exportCsv, exportJson, leadsToCsv, leadsToXlsxBuffer } from '../services/exportService.js';
import { listLeadsByCategory } from '../services/firebaseLeadStore.js';
import { getMultiJobSnapshot } from '../services/multiCategoryOrchestrator.js';
import { countryMeta } from '../data/countries.js';

const XLSX_CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

export async function exportAsCsv(_req, res) {
  const { leads } = getCurrentLeads();
  if (!leads.length) {
    return res.status(400).json({ error: 'No leads in memory to export' });
  }

  try {
    const filePath = await exportCsv(leads);
    const csv = leadsToCsv(leads);
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="leads.csv"');
    res.setHeader('X-Export-Path', filePath);
    return res.send(csv);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

export async function exportAsJson(_req, res) {
  const { leads } = getCurrentLeads();
  if (!leads.length) {
    return res.status(400).json({ error: 'No leads in memory to export' });
  }

  try {
    const filePath = await exportJson(leads);
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Content-Disposition', 'attachment; filename="leads.json"');
    res.setHeader('X-Export-Path', filePath);
    return res.json(leads);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/** GET /api/export/xlsx — the current single search's leads, one sheet. */
export async function exportAsXlsx(_req, res) {
  const { leads } = getCurrentLeads();
  if (!leads.length) {
    return res.status(400).json({ error: 'No leads in memory to export' });
  }

  try {
    const buffer = await leadsToXlsxBuffer([{ name: 'Leads', leads }]);
    res.setHeader('Content-Type', XLSX_CONTENT_TYPE);
    res.setHeader('Content-Disposition', 'attachment; filename="leads.xlsx"');
    return res.send(buffer);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

/**
 * GET /api/export/xlsx/multi — the most recent multi-category (and/or
 * multi-country) job, one sheet per category. Reads from Firestore rather
 * than the job's in-memory record, since the worker pool only keeps a
 * `leadsCollected` count once a category's leads are saved, not the leads
 * themselves — the saved category tag (e.g. "cleaning services UK") is the
 * only thing that still identifies which lead belongs to which sheet.
 */
export async function exportMultiAsXlsx(_req, res) {
  const snapshot = getMultiJobSnapshot();
  if (!snapshot || !snapshot.categories?.length) {
    return res.status(400).json({ error: 'No multi-category scan to export' });
  }

  try {
    const sheets = [];
    for (const c of snapshot.categories) {
      if (!c.leadsCollected) continue; // keep the workbook to categories that actually found something
      // The saved category always carries its country suffix (e.g. "cleaning
      // services UK"), even for a single-country job — `c.label` only adds
      // it when the job spans multiple countries, so it can't be reused
      // as the Firestore query value directly.
      const storedCategory = `${c.category} ${countryMeta(c.country).shortName}`;
      const leads = await listLeadsByCategory(storedCategory);
      sheets.push({ name: c.label, leads });
    }

    if (!sheets.length) {
      return res.status(400).json({ error: 'No saved leads found for this scan yet' });
    }

    const buffer = await leadsToXlsxBuffer(sheets);
    res.setHeader('Content-Type', XLSX_CONTENT_TYPE);
    res.setHeader('Content-Disposition', 'attachment; filename="scan-results.xlsx"');
    return res.send(buffer);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}
