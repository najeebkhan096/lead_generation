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
      link: bad.link || null,
    },
    searchId,
    source: lead.source || null,
    updatedAt: FieldValue.serverTimestamp(),
  };

  // Only include the WhatsApp check fields when this lead was actually
  // checked (Excel Archive validation). Omitting them otherwise lets
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

/**
 * Creates a `searches/{id}` record up front for a category/location run —
 * used by the state-city scan so leads can be written to Firestore one at a
 * time as they're found (see `upsertLeadToFirebase`) instead of only in one
 * big batch after the whole category finishes scanning.
 */
export async function createSearchRecord({ category, location, dateRange, nationwide = true, country = 'US' } = {}) {
  const db = getFirestore();
  const countrySuffix = countryMeta(country).shortName;
  const searchRef = db.collection('searches').doc();
  await searchRef.set({
    category: withCountrySuffix(category, countrySuffix),
    location: location || 'All US states',
    dateRange: dateRange || null,
    nationwide: Boolean(nationwide),
    leadCount: 0,
    createdAt: FieldValue.serverTimestamp(),
  });
  return searchRef.id;
}

/**
 * Writes ONE lead to Firestore immediately — the per-lead counterpart to
 * `saveLeadsToFirebase`'s batch write. Used by the state-city scan so a
 * lead (WhatsApp status included, if it was already checked) is durable in
 * Firestore the instant it's found, rather than only living in the
 * in-memory Excel archive until the entire category scan finishes.
 */
export async function upsertLeadToFirebase(lead, { searchId = null, country = 'US' } = {}) {
  const db = getFirestore();
  const countrySuffix = countryMeta(country).shortName;
  const id = leadDocId(lead);
  const ref = db.collection('leads').doc(id);
  const snap = await ref.get();
  const exists = snap.exists;

  const payload = toFirestoreLead(lead, searchId, countrySuffix);
  if (!exists) payload.createdAt = FieldValue.serverTimestamp();
  await ref.set(payload, { merge: true });

  if (searchId) {
    // Best-effort — losing an accurate leadCount on the search record is
    // harmless (it's just a display total), so this never blocks the save.
    db.collection('searches').doc(searchId).update({ leadCount: FieldValue.increment(1) }).catch(() => {});
  }

  return { inserted: !exists, dbId: id };
}

/** Firestore doc -> the API/export lead shape, shared by every lead-listing query. */
function docToLead(doc) {
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
}

export async function listFirebaseLeads({ limit = 500 } = {}) {
  const db = getFirestore();
  // Was hard-capped at 500 regardless of what callers asked for — since
  // the Dashboard and Leads page both request as many as they can to
  // compute accurate totals, that silently truncated real data (e.g.
  // showing "500 leads" when there were actually 3,000+).
  const lim = Math.min(Number(limit) || 500, 5000);
  const snap = await db
    .collection('leads')
    .orderBy('updatedAt', 'desc')
    .limit(lim)
    .get();

  const leads = snap.docs.map(docToLead);
  return { total: leads.length, leads, provider: 'firebase' };
}

/** Every saved lead in an exact category — e.g. for a per-scan Excel export. */
export async function listLeadsByCategory(category) {
  const db = getFirestore();
  const snap = await db.collection('leads').where('category', '==', category).get();
  return snap.docs.map(docToLead);
}

function stateKeyFromLocation(location) {
  const loc = String(location || '').trim();
  if (!loc) return '';
  const comma = loc.lastIndexOf(',');
  return (comma >= 0 ? loc.slice(comma + 1) : loc).trim();
}

function locationMatchesStates(location, wantedLower) {
  if (!wantedLower?.size) return true;
  const loc = String(location || '').trim().toLowerCase();
  if (!loc) return false;
  if (wantedLower.has(loc)) return true;
  const key = stateKeyFromLocation(location).toLowerCase();
  return Boolean(key) && wantedLower.has(key);
}

/**
 * Every saved lead that has not yet been checked for WhatsApp. No hard
 * cap — previously this stopped at 1000. Optional `states` (state names,
 * e.g. "California") filters on `location`, which the state-city scanner
 * stores as the state name.
 */
export async function listUnvalidatedLeads({ states } = {}) {
  const db = getFirestore();
  const wanted = Array.isArray(states) && states.length
    ? new Set(states.map((s) => String(s).trim().toLowerCase()).filter(Boolean))
    : null;

  const snap = await db.collection('leads').where('whatsAppCheckedAt', '==', null).get();
  const out = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    if (!d.phone) continue;
    if (wanted && !locationMatchesStates(d.location, wanted)) continue;
    out.push({
      id: doc.id,
      dbId: doc.id,
      phone: d.phone,
      business: d.business,
      location: d.location || null,
    });
  }
  return out;
}

/** Distinct state labels among unvalidated leads, with counts — used by
 * the WhatsApp Tool so the user can pick "all" vs a subset of states. */
export async function summarizeUnvalidatedLeads() {
  const leads = await listUnvalidatedLeads();
  const byState = new Map();
  for (const lead of leads) {
    const name = stateKeyFromLocation(lead.location) || 'Unknown';
    byState.set(name, (byState.get(name) || 0) + 1);
  }
  const locations = [...byState.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => a.name.localeCompare(b.name));
  return { total: leads.length, locations };
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
