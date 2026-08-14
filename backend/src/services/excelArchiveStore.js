import crypto from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore, getStorageBucket } from '../firebase/admin.js';

const COLLECTION = 'excelScans';
const STORAGE_PREFIX = 'excel-scans';
// Effectively permanent — this is a single-user internal tool, not a
// public-facing signed-download flow that needs short-lived links.
const SIGNED_URL_EXPIRES = '01-01-2100';

function docToRecord(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    fileName: data.fileName,
    storagePath: data.storagePath,
    downloadUrl: data.downloadUrl,
    categories: data.categories || [],
    countries: data.countries || [],
    totalLeads: data.totalLeads ?? 0,
    totalBusinessesProcessed: data.totalBusinessesProcessed ?? 0,
    // 'partial' — checkpointed mid-scan, more may still be appended.
    // 'complete' — the scan finished and this is the final workbook.
    status: data.status || 'complete',
    // Resume metadata — absent (null, not []) on archives created before
    // this field existed, so `resumeCategoryArchive` can tell "genuinely
    // zero countries done yet" apart from "unknown, derive from the
    // workbook's actual sheets instead."
    category: data.category || data.categories?.[0] || null,
    completedCountries: data.completedCountries ?? null,
    dateRange: data.dateRange ?? null,
    maxResultsPerState: data.maxResultsPerState ?? null,
    targetLeadCount: data.targetLeadCount ?? null,
    analyze: data.analyze ?? null,
    createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
  };
}

function slugify(text) {
  return String(text)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}

export function buildArchiveFileName({ categories, countries }) {
  const catPart = slugify(categories.slice(0, 2).join('-')) || 'scan';
  const countryPart = countries.length > 1 ? `-${countries.length}countries` : `-${slugify(countries[0] || '')}`;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return `${catPart}${countryPart}-${stamp}.xlsx`;
}

/**
 * Uploads an xlsx buffer to Firebase Storage and records/updates its
 * metadata in Firestore. Pass `id` to upsert the same doc + Storage object
 * in place instead of creating a new archive each time — used to checkpoint
 * an in-progress `exportOnly` scan (see multiCategoryOrchestrator.js)
 * without spamming the archive list with one entry per checkpoint.
 */
export async function uploadExcelArchive({
  id,
  buffer,
  fileName,
  categories,
  countries,
  totalLeads,
  totalBusinessesProcessed,
  status = 'complete',
  category,
  completedCountries,
  dateRange,
  maxResultsPerState,
  targetLeadCount,
  analyze,
}) {
  const bucket = getStorageBucket();
  const storagePath = `${STORAGE_PREFIX}/${fileName}`;
  const file = bucket.file(storagePath);

  await file.save(buffer, {
    contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    resumable: false,
  });

  const [downloadUrl] = await file.getSignedUrl({ action: 'read', expires: SIGNED_URL_EXPIRES });

  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id || crypto.randomUUID());
  const existing = await ref.get();
  await ref.set(
    {
      fileName,
      storagePath,
      downloadUrl,
      categories,
      countries,
      totalLeads,
      totalBusinessesProcessed,
      status,
      // Firestore rejects `undefined` field values outright — normalize so
      // a caller that omits any of these (e.g. an older call site) can't
      // crash the whole upload over an optional resume-metadata field.
      category: category ?? null,
      completedCountries: completedCountries ?? null,
      dateRange: dateRange ?? null,
      maxResultsPerState: maxResultsPerState ?? null,
      targetLeadCount: targetLeadCount ?? null,
      analyze: analyze ?? null,
      createdAt: existing.exists ? existing.data().createdAt : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return docToRecord(await ref.get());
}

export async function listExcelArchives() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).orderBy('createdAt', 'desc').get();
  return snap.docs.map(docToRecord);
}

export async function getExcelArchive(id) {
  const db = getFirestore();
  const doc = await db.collection(COLLECTION).doc(id).get();
  if (!doc.exists) return null;
  return docToRecord(doc);
}

export async function downloadExcelArchiveBuffer(id) {
  const record = await getExcelArchive(id);
  if (!record) return null;
  const bucket = getStorageBucket();
  const [buffer] = await bucket.file(record.storagePath).download();
  return { record, buffer };
}

export async function deleteExcelArchive(id) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const doc = await ref.get();
  if (!doc.exists) return false;
  const { storagePath } = doc.data();
  const bucket = getStorageBucket();
  try {
    await bucket.file(storagePath).delete();
  } catch {
    // File already gone from Storage — still clean up the Firestore record.
  }
  await ref.delete();
  return true;
}
