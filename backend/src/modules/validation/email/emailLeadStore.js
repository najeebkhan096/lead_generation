/**
 * Persist "email leads" — businesses whose website lists a contact email that
 * the email validator (`emailValidationJob.js`) found and verified — to their
 * own Firestore collection, `emailLeads`.
 *
 * The third lead signal alongside `leads` ("has a bad recent review") and
 * `websiteLeads` ("has no website"). Same doc-id scheme and upsert-with-merge
 * pattern as `websiteLeadStore.js`, so a business validated from several
 * archives is one document, not many.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../../firebase/admin.js';
import { countryMeta } from '../../../data/countries.js';
import { leadDocId, withCountrySuffix } from '../../../lib/leadIdentity.js';
import { pagedList, invalidateCategories } from '../../../lib/pagination.js';

const COLLECTION = 'emailLeads';

/** Same id the lead has in every other collection (see leadIdentity.js). */
export const emailLeadDocId = leadDocId;

function toFirestoreEmailLead(lead, { country } = {}) {
  const countrySuffix = country ? countryMeta(country).shortName : null;
  return {
    externalId: lead.id || null,
    business: lead.business || 'Unknown',
    category: withCountrySuffix(lead.category, countrySuffix),
    location: lead.location || null,
    searchLocation: lead.searchLocation || null,
    address: lead.address || null,
    phone: lead.phone || null,
    website: lead.website || null,
    mapsUrl: lead.mapsUrl || null,
    rating: lead.rating ?? null,
    totalReviews: lead.totalReviews ?? null,
    source: lead.source || null,
    email: lead.email,
    // Every distinct address found on the site, best first — `email` is
    // always `emails[0].email`.
    emails: Array.isArray(lead.emails) ? lead.emails : [],
    emailSource: lead.emailSource || null,
    // The page the address was read from — provenance for addresses found
    // by web search, so a human can eyeball where it came from.
    emailFoundOn: lead.emailFoundOn || null,
    // Only deliverable addresses are saved (see `emailValidationJob.js`),
    // but the status is kept so the UI can show what it was verified by.
    emailStatus: lead.emailStatus || 'valid',
    emailVerified: lead.emailVerified !== false,
    emailCheckedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Upserts leads that already have an email attached. Anything without one
 * is ignored — an email lead without an email isn't a lead.
 */
export async function saveEmailLeadsToFirebase(leadsInput, { country = null } = {}) {
  invalidateCategories(COLLECTION);
  const leads = Array.isArray(leadsInput) ? leadsInput.filter((l) => l?.email) : [];
  if (!leads.length) return { inserted: 0, updated: 0, total: 0 };

  const db = getFirestore();
  let inserted = 0;
  let updated = 0;

  const chunkSize = 400;
  for (let i = 0; i < leads.length; i += chunkSize) {
    const slice = leads.slice(i, i + chunkSize);
    const batch = db.batch();
    const ids = slice.map(emailLeadDocId);

    const existingSnaps = await Promise.all(
      ids.map((id) => db.collection(COLLECTION).doc(id).get())
    );

    slice.forEach((lead, idx) => {
      const ref = db.collection(COLLECTION).doc(ids[idx]);
      const exists = existingSnaps[idx].exists;
      if (exists) updated += 1;
      else inserted += 1;

      const payload = toFirestoreEmailLead(lead, { country });
      if (!exists) payload.createdAt = FieldValue.serverTimestamp();
      batch.set(ref, payload, { merge: true });
    });

    await batch.commit();
  }

  return { inserted, updated, total: leads.length };
}

function docToEmailLead(doc) {
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
    // Not a WhatsApp-checked lead type (same reasoning as website leads) —
    // a stale field on an old doc must never render as a verified status.
    hasWhatsApp: false,
    waLink: null,
    badReview: { stars: 1, text: '', date: 'Unknown' },
    email: d.email || null,
    emails: (d.emails || []).map((e) => (typeof e === 'string' ? e : e.email)).filter(Boolean),
    emailSource: d.emailSource || null,
    emailFoundOn: d.emailFoundOn || null,
    emailStatus: d.emailStatus || null,
    emailVerified: d.emailVerified === true,
    emailCheckedAt: d.emailCheckedAt?.toDate?.()?.toISOString?.() || null,
    savedAt: (d.createdAt || d.updatedAt)?.toDate?.()?.toISOString?.() || null,
  };
}

/** One page of email-verified leads, newest first — see `lib/pagination.js`. */
export async function listEmailLeads({ limit, cursor, category, q } = {}) {
  return pagedList({
    db: getFirestore(),
    collection: COLLECTION,
    mapDoc: docToEmailLead,
    limit,
    cursor,
    category,
    q,
  });
}

export async function deleteEmailLead(leadId) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(leadId);
  const snap = await ref.get();
  if (!snap.exists) {
    const err = new Error('Email lead not found');
    err.status = 404;
    throw err;
  }
  await ref.delete();
}

export async function deleteEmailLeadsByCategory(category) {
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

export async function getEmailLeadCount() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTION).count().get();
  return snap.data().count ?? 0;
}

export async function clearAllEmailLeads() {
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
