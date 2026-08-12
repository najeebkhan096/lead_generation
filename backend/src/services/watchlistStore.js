import crypto from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';

const COLLECTION = 'watchlist';

function docToEntry(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    url: data.url,
    name: data.name || null,
    country: data.country || 'US',
    addedAt: data.addedAt?.toDate?.()?.toISOString() || null,
    lastScannedAt: data.lastScannedAt?.toDate?.()?.toISOString() || null,
    lastRating: data.lastRating ?? null,
    lastTotalReviews: data.lastTotalReviews ?? null,
    lastNewReviewCount: data.lastNewReviewCount ?? 0,
    lastError: data.lastError || null,
    assignedTo: data.assignedTo || null,
    assignedToName: data.assignedToName || null,
  };
}

export async function addWatchlistEntry({ url, name, country = 'US', assignedTo, assignedToName }) {
  const db = getFirestore();
  const id = crypto.createHash('sha1').update(url).digest('hex').slice(0, 20);
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (existing.exists) {
    return docToEntry(existing);
  }
  await ref.set({
    url,
    name: name || null,
    country,
    addedAt: FieldValue.serverTimestamp(),
    lastScannedAt: null,
    lastReviewKeys: [],
    lastRating: null,
    lastTotalReviews: null,
    lastNewReviewCount: 0,
    lastError: null,
    assignedTo: assignedTo || null,
    assignedToName: assignedToName || null,
  });
  return docToEntry(await ref.get());
}

export async function assignWatchlistEntry(id, { assignedTo, assignedToName }) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  await ref.update({
    assignedTo: assignedTo || null,
    assignedToName: assignedToName || null,
  });
  return docToEntry(await ref.get());
}

export async function listWatchlistEntries() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).orderBy('addedAt', 'desc').get();
  return snap.docs.map(docToEntry);
}

export async function getWatchlistEntryRaw(id) {
  const db = getFirestore();
  const doc = await db.collection(COLLECTION).doc(id).get();
  if (!doc.exists) return null;
  return { id: doc.id, ...doc.data() };
}

export async function deleteWatchlistEntry(id) {
  const db = getFirestore();
  await db.collection(COLLECTION).doc(id).delete();
}

export async function recordScanResult(id, { reviewKeys, rating, totalReviews, newReviewCount, error }) {
  const db = getFirestore();
  await db.collection(COLLECTION).doc(id).update({
    lastScannedAt: FieldValue.serverTimestamp(),
    lastReviewKeys: reviewKeys,
    lastRating: rating ?? null,
    lastTotalReviews: totalReviews ?? null,
    lastNewReviewCount: newReviewCount ?? 0,
    lastError: error || null,
  });
}
