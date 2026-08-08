/**
 * Persist search session leads to Cloud Firestore.
 *
 * Collections:
 *   searches/{searchId}
 *   leads/{leadId}   — leadId derived from mapsUrl (or phone/name) for dedupe
 */

import crypto from 'crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';
import { getStore } from '../utils/memoryStore.js';
import { countryMeta } from '../data/countries.js';

function leadDocId(lead) {
  const maps = (lead.mapsUrl || '').split('?')[0].trim().toLowerCase();
  if (maps) return crypto.createHash('sha256').update(`maps:${maps}`).digest('hex').slice(0, 40);

  const phone = String(lead.phone || '').replace(/\D/g, '');
  if (phone) return crypto.createHash('sha256').update(`phone:${phone}`).digest('hex').slice(0, 40);

  const key = `${lead.business || ''}|${lead.address || ''}|${lead.location || ''}`.toLowerCase();
  return crypto.createHash('sha256').update(`name:${key}`).digest('hex').slice(0, 40);
}

/**
 * Tags a category with its country ("cleaning services" -> "cleaning
 * services USA") so the same category searched across different countries
 * doesn't collide — in the saved-leads category filter, or in
 * `checkIfCategorySearched`'s "already searched recently" dedupe check.
 */
function withCountrySuffix(category, countrySuffix) {
  const trimmed = String(category || '').trim();
  if (!trimmed) return null;
  if (trimmed.endsWith(countrySuffix)) return trimmed;
  return `${trimmed} ${countrySuffix}`;
}

function toFirestoreLead(lead, searchId, countrySuffix) {
  const bad = lead.badReview || {};
  const payload = {
    externalId: lead.id || null,
    business: lead.business || 'Unknown',
    category: withCountrySuffix(lead.category, countrySuffix),
    location: lead.location || null,
    address: lead.address || null,
    phone: lead.phone || null,
    website: lead.website || null,
    mapsUrl: lead.mapsUrl || null,
    rating: lead.rating ?? null,
    totalReviews: lead.totalReviews ?? null,
    waLink: lead.waLink || null,
    badReview: {
      stars: bad.stars ?? 1,
      text: bad.text || '',
      date: bad.date || 'Unknown',
      reviewer: bad.reviewer || null,
    },
    searchId,
    source: lead.source || null,
    whatsAppCheckedAt: null, // Default to null for unvalidated leads
    hasWhatsApp: false,
    updatedAt: FieldValue.serverTimestamp(),
  };

  // Only include the WhatsApp check fields when this lead was actually
  // checked during this scan (inline validation while scraping — see
  // leadService.js's inlineValidateWhatsApp). Omitting them otherwise lets
  // `merge: true` below leave an already-checked lead's status alone
  // instead of clobbering it back to "unchecked" the next time the same
  // lead resurfaces in a scrape.
  if (lead.whatsAppCheckedAt) {
    payload.hasWhatsApp = lead.hasWhatsApp === true;
    payload.whatsAppCheckedAt = Timestamp.fromDate(new Date(lead.whatsAppCheckedAt));
  }

  return payload;
}

/**
 * Save current in-memory leads (or provided list) to Firestore.
 */
export async function saveLeadsToFirebase(leadsInput) {
  const store = getStore();
  const leads = Array.isArray(leadsInput) && leadsInput.length ? leadsInput : store.leads;

  if (!leads.length) {
    const err = new Error('No leads to save. Run a search first.');
    err.status = 400;
    throw err;
  }

  const db = getFirestore();
  const last = store.lastSearch || {};
  const countrySuffix = countryMeta(last.country).shortName;

  const searchRef = db.collection('searches').doc();
  const searchPayload = {
    category: withCountrySuffix(last.category || leads[0]?.category, countrySuffix),
    location: last.location || 'All US states',
    dateRange: last.dateRange || null,
    nationwide: Boolean(last.nationwide),
    leadCount: leads.length,
    createdAt: FieldValue.serverTimestamp(),
  };

  await searchRef.set(searchPayload);

  let inserted = 0;
  let updated = 0;

  // Firestore batches max 500 ops
  const chunkSize = 400;
  for (let i = 0; i < leads.length; i += chunkSize) {
    const slice = leads.slice(i, i + chunkSize);
    const batch = db.batch();
    const ids = slice.map(leadDocId);

    const existingSnaps = await Promise.all(
      ids.map((id) => db.collection('leads').doc(id).get())
    );

    slice.forEach((lead, idx) => {
      const id = ids[idx];
      const ref = db.collection('leads').doc(id);
      const exists = existingSnaps[idx].exists;
      if (exists) updated += 1;
      else inserted += 1;

      const payload = toFirestoreLead(lead, searchRef.id, countrySuffix);
      if (!exists) {
        payload.createdAt = FieldValue.serverTimestamp();
      }
      batch.set(ref, payload, { merge: true });
    });

    await batch.commit();
  }

  const countSnap = await db.collection('leads').count().get();
  const totalInDb = countSnap.data().count ?? inserted + updated;

  return {
    provider: 'firebase',
    searchId: searchRef.id,
    inserted,
    updated,
    total: leads.length,
    totalInDb,
    message: `Saved ${leads.length} leads to Firebase (${inserted} new, ${updated} updated). Collection has ~${totalInDb} total.`,
  };
}

export async function listFirebaseLeads({ limit = 200 } = {}) {
  const db = getFirestore();
  const lim = Math.min(Number(limit) || 200, 500);
  const snap = await db
    .collection('leads')
    .orderBy('updatedAt', 'desc')
    .limit(lim)
    .get();

  const leads = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      dbId: doc.id,
      id: d.externalId || doc.id,
      business: d.business,
      category: d.category,
      location: d.location,
      address: d.address,
      phone: d.phone,
      website: d.website,
      mapsUrl: d.mapsUrl,
      rating: d.rating,
      totalReviews: d.totalReviews,
      hasWhatsApp: d.hasWhatsApp === true,
      waLink: d.waLink,
      badReview: d.badReview || { stars: 1, text: '', date: 'Unknown' },
      searchId: d.searchId,
      savedAt: d.updatedAt?.toDate?.()?.toISOString?.() || null,
      whatsAppCheckedAt: d.whatsAppCheckedAt?.toDate?.()?.toISOString?.() || null,
    };
  });

  return { total: leads.length, leads, provider: 'firebase' };
}

/**
 * Fetches leads that have not yet been checked for WhatsApp validation.
 */
export async function listUnvalidatedLeads({ limit = 100 } = {}) {
  const db = getFirestore();
  const snap = await db
    .collection('leads')
    .where('whatsAppCheckedAt', '==', null)
    .limit(Math.min(limit, 500))
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      dbId: doc.id,
      phone: d.phone,
      business: d.business,
    };
  });
}

/**
 * Flags a saved lead with the result of a real WhatsApp Web check.
 * `leadId` must be the Firestore document id (`dbId` in the API response
 * shape) — not the display `id`, which may be an externalId instead.
 */
export async function updateLeadWhatsAppStatus(leadId, { hasWhatsApp }) {
  const db = getFirestore();
  await db.collection('leads').doc(leadId).update({
    hasWhatsApp: Boolean(hasWhatsApp),
    whatsAppCheckedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Deletes a single saved lead. `leadId` must be the Firestore document id
 * (`dbId` in the API response shape) — not the display `id`.
 */
export async function deleteLead(leadId) {
  const db = getFirestore();
  const ref = db.collection('leads').doc(leadId);
  const snap = await ref.get();
  if (!snap.exists) {
    const err = new Error('Lead not found');
    err.status = 404;
    throw err;
  }
  await ref.delete();
}

/**
 * Deletes every saved lead in an exact category — e.g. "cleaning services
 * UK" (the country-tagged form leads are actually stored under, see
 * `withCountrySuffix`). Does not touch the `searches` collection.
 */
export async function deleteLeadsByCategory(category) {
  const db = getFirestore();
  const snap = await db.collection('leads').where('category', '==', category).get();
  const refs = snap.docs.map((doc) => doc.ref);

  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    refs.slice(i, i + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }

  return { deleted: refs.length };
}

export async function listFirebaseSearches({ limit = 50 } = {}) {
  const db = getFirestore();
  const snap = await db
    .collection('searches')
    .orderBy('createdAt', 'desc')
    .limit(Math.min(Number(limit) || 50, 200))
    .get();

  return {
    provider: 'firebase',
    searches: snap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        ...d,
        createdAt: d.createdAt?.toDate?.()?.toISOString?.() || null,
      };
    }),
  };
}

/**
 * Deletes every document in `leads` and `searches` — the only two
 * collections this app writes to (see firestore.rules). Firebase Auth
 * accounts live in a completely separate system and are never touched by
 * anything here, regardless.
 */
export async function clearAllData() {
  const db = getFirestore();
  const deleted = {};

  for (const name of ['leads', 'searches']) {
    const refs = await db.collection(name).listDocuments();
    deleted[name] = refs.length;
    for (let i = 0; i < refs.length; i += 400) {
      const batch = db.batch();
      refs.slice(i, i + 400).forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
  }

  return {
    deleted,
    message: `Cleared ${deleted.leads} lead(s) and ${deleted.searches} search record(s). User accounts were not affected.`,
  };
}

export async function getFirebaseLeadCount() {
  const db = getFirestore();
  const snap = await db.collection('leads').count().get();
  return snap.data().count ?? 0;
}

/**
 * Checks if a specific category (for a given country) has already been
 * searched within the last N days. `country` must match what the category
 * was actually tagged with in `searches` (see `withCountrySuffix`) — the
 * same category name searched for a different country is not a duplicate.
 */
export async function checkIfCategorySearched(category, country, days = 7) {
  if (!category) return false;
  const taggedCategory = withCountrySuffix(category, countryMeta(country).shortName);
  const db = getFirestore();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);

  const snap = await db
    .collection('searches')
    .where('category', '==', taggedCategory)
    .where('createdAt', '>', cutoff)
    .limit(1)
    .get();

  return !snap.empty;
}
