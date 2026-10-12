/**
 * Persist WhatsApp-verified leads — businesses whose phone number a real
 * WhatsApp Web check confirmed is registered — to their own Firestore
 * collection, `whatsappLeads`.
 *
 * The WhatsApp counterpart to `emailLeads`: validating a lead (from a saved
 * review/website lead or from an Excel archive) *copies* it here, so the
 * verified list is a first-class collection that can be browsed, exported
 * and read by the mobile app without digging through scan workbooks. The
 * source lead is never moved or modified by this store.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../../firebase/admin.js';
import { leadDocId, normalizeCategory } from '../../../lib/leadIdentity.js';
import { pagedList, invalidateCategories } from '../../../lib/pagination.js';
import { normalizePhone, waMeLink } from './whatsappChecker.js';

const COLLECTION = 'whatsappLeads';

/** Same id the business has in every other lead collection. */
export const whatsappLeadDocId = leadDocId;

function waLinkFor(lead) {
  if (lead.waLink) return lead.waLink;
  const e164 = normalizePhone(lead.phone);
  return waMeLink(e164);
}

/**
 * `sourceType` says which signal produced the lead, so the verified list
 * can be filtered the same way the source lists are: a lead that carries a
 * review is a review lead; one without is treated as a no-website lead.
 */
function inferSourceType(lead) {
  if (lead.sourceType) return lead.sourceType;
  return lead.badReview?.text ? 'review' : 'website';
}

function toFirestoreWhatsAppLead(lead, { country } = {}) {
  const bad = lead.badReview || {};
  return {
    externalId: lead.id || null,
    // Firestore id of the saved lead this was validated from, when there
    // is one (archive leads were never saved, so this is null for them).
    sourceId: lead.dbId || null,
    sourceType: inferSourceType(lead),
    business: lead.business || 'Unknown',
    category: normalizeCategory(lead.category, country),
    location: lead.location || null,
    address: lead.address || null,
    phone: lead.phone || null,
    waLink: waLinkFor(lead),
    website: lead.website || null,
    mapsUrl: lead.mapsUrl || null,
    rating: lead.rating ?? null,
    totalReviews: lead.totalReviews ?? null,
    badReview: {
      stars: bad.stars ?? null,
      text: bad.text || '',
      date: bad.date || null,
      reviewer: bad.reviewer || null,
      link: bad.link || null,
    },
    source: lead.source || null,
    whatsAppCheckedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Upserts verified leads. Anything without a phone number is ignored —
 * a WhatsApp lead is the phone number.
 */
export async function saveWhatsAppLeadsToFirebase(leadsInput, { country = null } = {}) {
  invalidateCategories(COLLECTION);
  const leads = Array.isArray(leadsInput) ? leadsInput.filter((l) => l?.phone) : [];
  if (!leads.length) return { inserted: 0, updated: 0, total: 0 };

  const db = getFirestore();
  let inserted = 0;
  let updated = 0;

  const chunkSize = 400;
  for (let i = 0; i < leads.length; i += chunkSize) {
    const slice = leads.slice(i, i + chunkSize);
    const batch = db.batch();
    const ids = slice.map(leadDocId);
    const existing = await db.getAll(...ids.map((id) => db.collection(COLLECTION).doc(id)));

    slice.forEach((lead, idx) => {
      const ref = db.collection(COLLECTION).doc(ids[idx]);
      const exists = existing[idx].exists;
      if (exists) updated += 1;
      else inserted += 1;

      const payload = toFirestoreWhatsAppLead(lead, { country });
      if (!exists) payload.createdAt = FieldValue.serverTimestamp();
      batch.set(ref, payload, { merge: true });
    });

    await batch.commit();
  }

  return { inserted, updated, total: leads.length };
}

function docToWhatsAppLead(doc) {
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
    hasWhatsApp: true,
    waLink: d.waLink || null,
    sourceType: d.sourceType || null,
    badReview: {
      stars: d.badReview?.stars ?? 1,
      text: d.badReview?.text || '',
      date: d.badReview?.date || 'Unknown',
      reviewer: d.badReview?.reviewer || null,
    },
    whatsAppCheckedAt: d.whatsAppCheckedAt?.toDate?.()?.toISOString?.() || null,
    savedAt: (d.createdAt || d.updatedAt)?.toDate?.()?.toISOString?.() || null,
  };
}

/** One page of WhatsApp-verified leads, newest first. `sourceType` narrows
 * to `review` or `website` leads. */
export async function listWhatsAppLeads({ limit, cursor, category, q, sourceType } = {}) {
  return pagedList({
    db: getFirestore(),
    collection: COLLECTION,
    mapDoc: docToWhatsAppLead,
    limit,
    cursor,
    category,
    q,
    where: sourceType ? [['sourceType', '==', sourceType]] : [],
  });
}

/** Which of [ids] are already verified WhatsApp leads. */
export async function getVerifiedWhatsAppIds(ids) {
  const unique = [...new Set(ids)];
  const out = new Set();
  if (!unique.length) return out;
  const db = getFirestore();
  for (let i = 0; i < unique.length; i += 300) {
    const slice = unique.slice(i, i + 300);
    const snaps = await db.getAll(...slice.map((id) => db.collection(COLLECTION).doc(id)));
    snaps.forEach((snap, idx) => {
      if (snap.exists) out.add(slice[idx]);
    });
  }
  return out;
}

export async function deleteWhatsAppLead(leadId) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(leadId);
  const snap = await ref.get();
  if (!snap.exists) {
    const err = new Error('WhatsApp lead not found');
    err.status = 404;
    throw err;
  }
  await ref.delete();
}

export async function deleteWhatsAppLeadsByCategory(category) {
  invalidateCategories(COLLECTION);
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

export async function getWhatsAppLeadCount() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).count().get();
  return snap.data().count ?? 0;
}

export async function clearAllWhatsAppLeads() {
  invalidateCategories(COLLECTION);
  const db = getFirestore();
  const refs = await db.collection(COLLECTION).listDocuments();
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    refs.slice(i, i + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
  return { deleted: refs.length };
}
