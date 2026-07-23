/**
 * Export in-memory leads to CSV / JSON under /exports (local files only).
 */

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const EXPORTS_DIR = path.resolve(__dirname, '../../exports');

async function ensureExportsDir() {
  await fs.mkdir(EXPORTS_DIR, { recursive: true });
}

function escapeCsv(value) {
  const str = value == null ? '' : String(value);
  if (/[",\n\r]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

export function leadsToCsv(leads) {
  const header = [
    'Business Name',
    'Phone',
    'Has WhatsApp',
    'WhatsApp Link',
    'Website',
    'Location',
    'Address',
    'Category',
    'Rating',
    'Review',
    'Review Date',
    'Maps URL',
  ];

  const rows = leads.map((lead) =>
    [
      lead.business,
      lead.phone,
      lead.hasWhatsApp ? 'Yes' : 'No',
      lead.waLink || '',
      lead.website,
      lead.location,
      lead.address,
      lead.category,
      lead.rating,
      lead.badReview?.text,
      lead.badReview?.date,
      lead.mapsUrl,
    ]
      .map(escapeCsv)
      .join(',')
  );

  return [header.join(','), ...rows].join('\n');
}

export async function exportJson(leads, filename = 'leads.json') {
  await ensureExportsDir();
  const filePath = path.join(EXPORTS_DIR, filename);
  await fs.writeFile(filePath, JSON.stringify(leads, null, 2), 'utf8');
  return filePath;
}

export async function exportCsv(leads, filename = 'leads.csv') {
  await ensureExportsDir();
  const filePath = path.join(EXPORTS_DIR, filename);
  await fs.writeFile(filePath, leadsToCsv(leads), 'utf8');
  return filePath;
}

export function getExportsDir() {
  return EXPORTS_DIR;
}
