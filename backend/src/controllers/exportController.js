import { getCurrentLeads } from '../services/leadService.js';
import { exportCsv, exportJson, leadsToCsv } from '../services/exportService.js';

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
