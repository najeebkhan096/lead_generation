/**
 * Export in-memory leads to CSV / JSON / XLSX under /exports (local files only).
 */

import fs from 'fs/promises';
import path from 'path';
import ExcelJS from 'exceljs';
import { EXPORTS_DIR } from '../../lib/paths.js';


async function ensureExportsDir() {
  await fs.mkdir(EXPORTS_DIR, { recursive: true });
}

/** Shared column definitions so CSV and XLSX exports stay in sync. */
const LEAD_COLUMNS = [
  { header: 'Business Name', key: 'business', width: 32 },
  { header: 'Phone', key: 'phone', width: 18 },
  { header: 'Has WhatsApp', key: 'hasWhatsAppLabel', width: 13 },
  { header: 'WhatsApp Link', key: 'waLink', width: 30 },
  { header: 'Website', key: 'website', width: 30 },
  { header: 'Location', key: 'location', width: 18 },
  { header: 'Address', key: 'address', width: 34 },
  { header: 'Category', key: 'category', width: 22 },
  { header: 'Rating', key: 'rating', width: 8 },
  { header: 'Review', key: 'reviewText', width: 40 },
  { header: 'Review Date', key: 'reviewDate', width: 14 },
  { header: 'Maps URL', key: 'mapsUrl', width: 30 },
];

/** Appended after `LEAD_COLUMNS` for email-verified exports only, so every
 * other workbook this app writes keeps its exact existing layout. */
const EMAIL_COLUMNS = [
  { header: 'Email', key: 'email', width: 32 },
  { header: 'Email Source', key: 'emailSource', width: 16 },
  { header: 'Other Emails', key: 'otherEmails', width: 36 },
];

function leadRow(lead) {
  return {
    business: lead.business,
    phone: lead.phone,
    hasWhatsAppLabel: lead.hasWhatsApp ? 'Yes' : 'No',
    waLink: lead.waLink || '',
    website: lead.website,
    location: lead.location,
    address: lead.address,
    category: lead.category,
    rating: lead.rating,
    reviewText: lead.badReview?.text,
    reviewDate: lead.badReview?.date,
    mapsUrl: lead.mapsUrl,
    email: lead.email || '',
    emailSource: lead.emailSource || '',
    otherEmails: (lead.emails || []).filter((e) => e !== lead.email).join(', '),
  };
}

/**
 * Excel sheet names can't exceed 31 chars or contain : \ / ? * [ ], and
 * must be unique within the workbook — category labels like "cleaning
 * services · United Kingdom" can violate all three, so every candidate
 * name gets sanitized and de-duplicated here.
 */
function safeSheetName(name, used) {
  let base = String(name || 'Sheet')
    .replace(/[:\\/?*[\]]/g, '-')
    .trim()
    .slice(0, 31) || 'Sheet';

  let candidate = base;
  let n = 2;
  while (used.has(candidate.toLowerCase())) {
    const suffix = ` (${n})`;
    candidate = `${base.slice(0, 31 - suffix.length)}${suffix}`;
    n += 1;
  }
  used.add(candidate.toLowerCase());
  return candidate;
}

/**
 * One workbook, one worksheet per entry in `sheets` — used both for a
 * single search (one sheet) and a multi-category/multi-country job (one
 * sheet per category, e.g. "cleaning services UK", "cleaning services DE").
 * @param {{ name: string, leads: object[] }[]} sheets
 * @param {{ withEmail?: boolean }} [options] adds the Email columns — only
 *   the email-verified archive uses them.
 * @returns {Promise<Buffer>}
 */
export async function leadsToXlsxBuffer(sheets, { withEmail = false } = {}) {
  const columns = withEmail ? [...LEAD_COLUMNS, ...EMAIL_COLUMNS] : LEAD_COLUMNS;
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'LeadFinder';
  workbook.created = new Date();

  const usedNames = new Set();

  for (const { name, leads } of sheets) {
    const sheet = workbook.addWorksheet(safeSheetName(name, usedNames));
    sheet.columns = columns;
    sheet.getRow(1).font = { bold: true };
    sheet.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: columns.length } };
    for (const lead of leads) {
      sheet.addRow(leadRow(lead));
    }
  }

  // A workbook needs at least one sheet even if every category came back empty.
  if (!sheets.length) {
    workbook.addWorksheet('Leads').columns = columns;
  }

  return workbook.xlsx.writeBuffer();
}

/**
 * The same workbook as [leadsToXlsxBuffer], written to a file one row at a
 * time. `sheets` is `[{ name, leads }]` where `leads` is an async iterable, so
 * a scan can write a workbook of any size without holding it in memory. Strings
 * are written inline rather than through a shared table, which would otherwise
 * grow with every distinct business name.
 */
export async function writeLeadsXlsxFile(filePath, sheets, { withEmail = false } = {}) {
  const columns = withEmail ? [...LEAD_COLUMNS, ...EMAIL_COLUMNS] : LEAD_COLUMNS;
  const workbook = new ExcelJS.stream.xlsx.WorkbookWriter({
    filename: filePath,
    useSharedStrings: false,
    useStyles: true,
  });
  workbook.creator = 'LeadFinder';
  workbook.created = new Date();

  const usedNames = new Set();
  for (const { name, leads } of sheets) {
    const sheet = workbook.addWorksheet(safeSheetName(name, usedNames));
    sheet.columns = columns;
    sheet.getRow(1).font = { bold: true };
    sheet.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: columns.length } };
    for await (const lead of leads) {
      sheet.addRow(leadRow(lead)).commit();
    }
    sheet.commit();
  }

  // A workbook needs at least one sheet even if every category came back empty.
  if (!sheets.length) {
    const sheet = workbook.addWorksheet('Leads');
    sheet.columns = columns;
    sheet.commit();
  }

  await workbook.commit();
  return filePath;
}

/**
 * Reads an .xlsx buffer back into plain JSON — used to show an archived
 * scan's data in the web/mobile UI without shipping an xlsx-parsing
 * library to either client. Assumes row 1 is a header row (true for
 * every workbook this app produces via [leadsToXlsxBuffer]).
 */
export async function xlsxBufferToJson(buffer) {
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);

  return workbook.worksheets.map((sheet) => {
    const headerRow = sheet.getRow(1);
    const headers = [];
    headerRow.eachCell({ includeEmpty: true }, (cell, colNumber) => {
      headers[colNumber] = String(cell.value ?? '');
    });

    const rows = [];
    for (let r = 2; r <= sheet.rowCount; r++) {
      const row = sheet.getRow(r);
      if (row.cellCount === 0) continue;
      const obj = {};
      let hasValue = false;
      row.eachCell({ includeEmpty: true }, (cell, colNumber) => {
        const header = headers[colNumber];
        if (!header) return;
        const value = cell.value;
        obj[header] = value && typeof value === 'object' && 'text' in value ? value.text : (value ?? '');
        if (obj[header] !== '') hasValue = true;
      });
      if (hasValue) rows.push(obj);
    }

    return { name: sheet.name, headers: headers.filter(Boolean), rows };
  });
}

/**
 * Converts the generic {headers, rows} shape from [xlsxBufferToJson] into
 * the same lead JSON shape `/api/search/results` and `/api/db/leads`
 * return, so the frontend can render archived rows with the exact `Lead`
 * entity / `LeadCard` widget it already uses everywhere else. `idPrefix`
 * namespaces the synthetic ids (e.g. `archive-<archiveId>`) since these
 * leads were never saved to Firestore and have no real doc id.
 */
export function sheetsToLeadsJson(sheets, idPrefix) {
  const leads = [];
  let i = 0;
  for (const sheet of sheets) {
    for (const row of sheet.rows) {
      i += 1;
      const rating = row['Rating'];
      leads.push({
        id: `${idPrefix}-${i}`,
        dbId: null,
        business: row['Business Name'] || '',
        category: row['Category'] || sheet.name,
        location: row['Location'] || '',
        address: row['Address'] || null,
        phone: row['Phone'] || null,
        website: row['Website'] || null,
        mapsUrl: row['Maps URL'] || null,
        rating: typeof rating === 'number' ? rating : (rating ? Number(rating) || null : null),
        hasWhatsApp: row['Has WhatsApp'] === 'Yes',
        waLink: row['WhatsApp Link'] || null,
        // Only present in email-verified workbooks; null everywhere else.
        email: row['Email'] || null,
        emailSource: row['Email Source'] || null,
        emails: [row['Email'], ...String(row['Other Emails'] || '').split(',')]
          .map((e) => String(e || '').trim())
          .filter(Boolean),
        badReview: {
          stars: null,
          text: row['Review'] || '',
          date: row['Review Date'] || 'Unknown',
          reviewer: null,
        },
      });
    }
  }
  return leads;
}

export async function exportXlsx(sheets, filename = 'leads.xlsx') {
  await ensureExportsDir();
  const filePath = path.join(EXPORTS_DIR, filename);
  const buffer = await leadsToXlsxBuffer(sheets);
  await fs.writeFile(filePath, buffer);
  return filePath;
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
