/**
 * Persist "website leads" — businesses discovered during a scan that have
 * no website at all — to their own Firestore collection, `websiteLeads`.
 *
 * Mirrors `firebaseLeadStore.js`'s `leads` collection (same doc-id scheme,
 * same upsert-with-merge pattern) so the two feel like the same feature to
 * anything reading/writing them, just filtered on the opposite signal:
 * `leads` is "has a bad recent review", `websiteLeads` is "has no website".
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { countryMeta } from '../../data/countries.js';
import { leadDocId, withCountrySuffix } from '../../lib/leadIdentity.js';

const COLLECTION = 'websiteLeads';

/**
 * Website leads ("no website found") are a different signal from review
 * leads. A scan saves them without any WhatsApp fields; those are added
 * later, only if the lead is run through the WhatsApp validator.
 */
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
    // Set by the WhatsApp validator (`updateWebsiteLeadWhatsAppStatus`);
    // a lead that was never checked is simply unverified.
    hasWhatsApp: d.hasWhatsApp === true,
    waLink: d.waLink || null,
    whatsAppCheckedAt: d.whatsAppCheckedAt?.toDate?.()?.toISOString?.() || null,
    badReview: { stars: 1, text: '', date: 'Unknown' },
    savedAt: d.updatedAt?.toDate?.()?.toISOString?.() || null,
    email: d.email || null,
    emailSource: d.emailSource || null,
    emailFoundOn: d.emailFoundOn || null,
    emailOutreachStatus: d.emailOutreachStatus || null,
    emailSentAt: d.emailSentAt?.toDate?.()?.toISOString?.() || null,
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

/** Raw website-lead docs for the given Firestore ids, as the plain objects
 * `docToWebsiteLead` returns. Ids that no longer exist are simply absent. */
export async function getWebsiteLeadsByIds(ids) {
  const unique = [...new Set((ids || []).map(String).filter(Boolean))];
  if (!unique.length) return [];
  const db = getFirestore();
  const snaps = await db.getAll(...unique.map((id) => db.collection(COLLECTION).doc(id)));
  return snaps.filter((s) => s.exists).map(docToWebsiteLead);
}

/**
 * Records a verified email on the website lead itself — outreach enrolls a
 * lead using the `email` on its source doc, so this is what makes a
 * website lead outreach-ready. Never touches `emailOutreachStatus`.
 */
export async function setWebsiteLeadEmail(leadId, { email, emails, emailSource, emailFoundOn }) {
  const db = getFirestore();
  const patch = {
    email,
    emails: emails || [],
    emailSource: emailSource || null,
    emailFoundOn: emailFoundOn || null,
    emailVerified: true,
    emailCheckedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await db.collection(COLLECTION).doc(leadId).set(patch, { merge: true });
}

/**
 * Flags a saved website lead with the result of a real WhatsApp check.
 * `leadId` must be the Firestore document id (`dbId`).
 */
export async function updateWebsiteLeadWhatsAppStatus(leadId, { hasWhatsApp }) {
  const db = getFirestore();
  await db.collection(COLLECTION).doc(leadId).set(
    {
      hasWhatsApp: Boolean(hasWhatsApp),
      whatsAppCheckedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
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
