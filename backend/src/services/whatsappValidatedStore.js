import crypto from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore, getStorageBucket } from '../firebase/admin.js';

const COLLECTION = 'whatsappValidatedScans';
const STORAGE_PREFIX = 'whatsapp-validated-scans';
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
    sourceArchiveId: data.sourceArchiveId || null,
    sourceFileName: data.sourceFileName || null,
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

export function buildValidatedFileName({ categories }) {
  const catPart = slugify((categories || []).slice(0, 2).join('-')) || 'whatsapp-verified';
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return `whatsapp-verified-${catPart}-${stamp}.xlsx`;
}

/** Uploads a validated-businesses xlsx buffer to Firebase Storage and records its metadata in Firestore. */
export async function uploadValidatedArchive({
  buffer,
  fileName,
  categories,
  countries,
  totalLeads,
  sourceArchiveId,
  sourceFileName,
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
  const ref = db.collection(COLLECTION).doc(crypto.randomUUID());
  await ref.set({
    fileName,
    storagePath,
    downloadUrl,
    categories,
    countries: countries || [],
    totalLeads,
    sourceArchiveId: sourceArchiveId || null,
    sourceFileName: sourceFileName || null,
    createdAt: FieldValue.serverTimestamp(),
  });

  return docToRecord(await ref.get());
}

export async function listValidatedArchives() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).orderBy('createdAt', 'desc').get();
  return snap.docs.map(docToRecord);
}

export async function getValidatedArchive(id) {
  const db = getFirestore();
  const doc = await db.collection(COLLECTION).doc(id).get();
  if (!doc.exists) return null;
  return docToRecord(doc);
}

export async function downloadValidatedArchiveBuffer(id) {
  const record = await getValidatedArchive(id);
  if (!record) return null;
  const bucket = getStorageBucket();
  const [buffer] = await bucket.file(record.storagePath).download();
  return { record, buffer };
}

export async function deleteValidatedArchive(id) {
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
