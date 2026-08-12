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
    createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
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

/** Uploads an xlsx buffer to Firebase Storage and records its metadata in Firestore. */
export async function uploadExcelArchive({ buffer, fileName, categories, countries, totalLeads, totalBusinessesProcessed }) {
  const bucket = getStorageBucket();
  const storagePath = `${STORAGE_PREFIX}/${fileName}`;
  const file = bucket.file(storagePath);

  await file.save(buffer, {
    contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    resumable: false,
  });

  const [downloadUrl] = await file.getSignedUrl({ action: 'read', expires: SIGNED_URL_EXPIRES });

  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(crypto.randomUUID());
  await ref.set({
    fileName,
    storagePath,
    downloadUrl,
    categories,
    countries,
    totalLeads,
    totalBusinessesProcessed,
    createdAt: FieldValue.serverTimestamp(),
  });

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
