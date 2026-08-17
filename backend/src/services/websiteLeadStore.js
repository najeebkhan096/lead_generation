/**
 * Persist "website leads" — businesses discovered during a scan that have
 * no website at all — to their own Firestore collection, `websiteLeads`.
 *
 * Mirrors `firebaseLeadStore.js`'s `leads` collection (same doc-id scheme,
 * same upsert-with-merge pattern) so the two feel like the same feature to
 * anything reading/writing them, just filtered on the opposite signal:
 * `leads` is "has a bad recent review", `websiteLeads` is "has no website".
 */

import crypto from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';
import { countryMeta } from '../data/countries.js';

const COLLECTION = 'websiteLeads';

function leadDocId(lead) {
  const maps = (lead.mapsUrl || '').split('?')[0].trim().toLowerCase();
  if (maps) return crypto.createHash('sha256').update(`maps:${maps}`).digest('hex').slice(0, 40);

  const phone = String(lead.phone || '').replace(/\D/g, '');
  if (phone) return crypto.createHash('sha256').update(`phone:${phone}`).digest('hex').slice(0, 40);

  const key = `${lead.business || ''}|${lead.address || ''}|${lead.location || ''}`.toLowerCase();
  return crypto.createHash('sha256').update(`name:${key}`).digest('hex').slice(0, 40);
}

/** Same "cleaning services USA" country tagging `firebaseLeadStore.js` uses
 * for `leads`, kept in sync so the same category collides/dedupes the same
 * way in both collections. */
function withCountrySuffix(category, countrySuffix) {
  const trimmed = String(category || '').trim();
  if (!trimmed) return null;
  if (!countrySuffix || trimmed.endsWith(countrySuffix)) return trimmed;
  return `${trimmed} ${countrySuffix}`;
}

function toFirestoreWebsiteLead(lead, { searchLocation, country } = {}) {
  const countrySuffix = countryMeta(country).shortName;
  return {
    externalId: lead.id || null,
    business: lead.business || 'Unknown',
    category: withCountrySuffix(lead.category, countrySuffix),
    location: lead.location || null,
    searchLocation: lead.searchLocation || searchLocation || null,
    address: lead.address || null,
    phone: lead.phone || null,
    website: null,
    mapsUrl: lead.mapsUrl || null,
    rating: lead.rating ?? null,
    totalReviews: lead.totalReviews ?? null,
    waLink: lead.waLink || null,
    hasWhatsApp: lead.hasWhatsApp === true,
    source: lead.source || null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Upserts a batch of no-website leads found during a scan. Safe to call
 * with an empty/undefined list (no-op) so callers don't need to guard —
 * every scan pipeline hook calls this unconditionally after scraping a
 * location.
 */
export async function saveWebsiteLeadsToFirebase(leadsInput, { country = 'US' } = {}) {
  const leads = Array.isArray(leadsInput) ? leadsInput.filter((l) => !l.website) : [];
  if (!leads.length) return { inserted: 0, updated: 0, total: 0 };

  const db = getFirestore();
  let inserted = 0;
  let updated = 0;

  const chunkSize = 400;
  for (let i = 0; i < leads.length; i += chunkSize) {
    const slice = leads.slice(i, i + chunkSize);
    const batch = db.batch();
    const ids = slice.map(leadDocId);

    const existingSnaps = await Promise.all(
      ids.map((id) => db.collection(COLLECTION).doc(id).get())
    );

    slice.forEach((lead, idx) => {
      const id = ids[idx];
      const ref = db.collection(COLLECTION).doc(id);
      const exists = existingSnaps[idx].exists;
      if (exists) updated += 1;
      else inserted += 1;

      const payload = toFirestoreWebsiteLead(lead, { country });
      if (!exists) {
        payload.createdAt = FieldValue.serverTimestamp();
      }
      batch.set(ref, payload, { merge: true });
    });

    await batch.commit();
  }

  return { inserted, updated, total: leads.length };
}

function docToWebsiteLead(doc) {
  const d = doc.data();
  return {
    dbId: doc.id,
    id: d.externalId || doc.id,
    business: d.business,
    category: d.category,
    location: d.location,
    address: d.address,
    phone: d.phone,
    website: d.website || null,
    mapsUrl: d.mapsUrl,
    rating: d.rating,
    totalReviews: d.totalReviews,
    hasWhatsApp: d.hasWhatsApp === true,
    waLink: d.waLink,
    badReview: { stars: 1, text: '', date: 'Unknown' },
    savedAt: d.updatedAt?.toDate?.()?.toISOString?.() || null,
  };
}

export async function listWebsiteLeads({ limit = 500 } = {}) {
  const db = getFirestore();
  const lim = Math.min(Number(limit) || 500, 5000);
  const snap = await db
    .collection(COLLECTION)
    .orderBy('updatedAt', 'desc')
    .limit(lim)
    .get();

  const leads = snap.docs.map(docToWebsiteLead);
  return { total: leads.length, leads, provider: 'firebase' };
}

export async function deleteWebsiteLead(leadId) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(leadId);
  const snap = await ref.get();
  if (!snap.exists) {
    const err = new Error('Website lead not found');
    err.status = 404;
    throw err;
  }
  await ref.delete();
}

export async function deleteWebsiteLeadsByCategory(category) {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).where('category', '==', category).get();
  const refs = snap.docs.map((doc) => doc.ref);

  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    refs.slice(i, i + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }

  return { deleted: refs.length };
}

export async function getWebsiteLeadCount() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).count().get();
  return snap.data().count ?? 0;
}

export async function clearAllWebsiteLeads() {
  const db = getFirestore();
  const refs = await db.collection(COLLECTION).listDocuments();
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    refs.slice(i, i + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
  return { deleted: refs.length };
}
