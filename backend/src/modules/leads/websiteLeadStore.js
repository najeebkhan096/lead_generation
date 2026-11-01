/**
 * Website leads — businesses Google Maps lists with NO website — in their own
 * Firestore collection, `websiteLeads`.
 *
 * Same identity as every other lead collection (`leadDocId`), so a business
 * that is both a no-website lead and a 1-star review lead is one id in
 * `websiteLeads` and in `leads`, never two records in the same collection, and
 * a re-scan updates its document instead of adding another.
 *
 * Only a CONFIRMED absence is stored. A business whose website could not be
 * read (timeout, page not loaded) is never written here; see
 * `recordWebsiteUnknown` in validation/leadChecks.js.
 *
 *   websiteLeads/{id} = {
 *     business, category, location, address, phone, waLink, mapsUrl,
 *     rating, totalReviews, source,
 *     websiteStatus: 'missing' (→ 'available' if a later scan finds a site),
 *     websiteCheckedAt, leadTypes: ['no_website', 'review'?],
 *     createdAt, updatedAt
 *   }
 */

import { getFirestore } from '../../firebase/admin.js';
import { leadDocId, normalizeCategory } from '../../lib/leadIdentity.js';
import { pagedList, invalidateCategories } from '../../lib/pagination.js';

const COLLECTION = 'websiteLeads';

/** Same id the business has in every other lead collection. */
export const websiteLeadDocId = leadDocId;

/** Drops null/undefined/empty values so a thinner scan never blanks a stored field. */
export function compact(object) {
  return Object.fromEntries(Object.entries(object).filter(([, v]) => v !== null && v !== undefined && v !== ''));
}

export function unionList(existing, added) {
  return [...new Set([...(Array.isArray(existing) ? existing : []), ...(added || [])])];
}

/** The business details every site-based lead carries, without empty values. */
export function businessFields(site) {
  return compact({
    externalId: site.id,
    business: site.business,
    category: normalizeCategory(site.category, site.country),
    location: site.location,
    address: site.address,
    phone: site.phone,
    waLink: site.waLink,
    mapsUrl: site.mapsUrl,
    rating: site.rating,
    totalReviews: site.totalReviews,
    source: site.source,
  });
}

/**
 * The document to write for a no-website business. Pure: [existing] is the
 * stored data (or undefined) and the result is a merge patch — fields the scan
 * did not learn are left out, so what is already stored is never erased.
 */
export function buildWebsiteLeadPatch(existing, site, now = new Date()) {
  const patch = {
    ...businessFields(site),
    business: site.business || existing?.business || 'Unknown',
    websiteStatus: 'missing',
    websiteCheckedAt: now,
    leadTypes: unionList(existing?.leadTypes, ['no_website', ...(site.leadTypes || [])]),
    updatedAt: now,
  };
  if (!existing) patch.createdAt = now;
  return patch;
}

/**
 * Upserts confirmed no-website businesses. Idempotent: the same business
 * scanned again updates its one document.
 *
 * @returns {Promise<{inserted: number, updated: number}>}
 */
export async function saveWebsiteLeads(sites, { db = getFirestore(), now = new Date() } = {}) {
  const list = (Array.isArray(sites) ? sites : []).filter((s) => s?.business);
  if (!list.length) return { inserted: 0, updated: 0 };
  invalidateCategories(COLLECTION);

  // One document per business, even if a city listed it twice.
  const unique = new Map();
  for (const site of list) unique.set(websiteLeadDocId(site), site);

  let inserted = 0;
  let updated = 0;
  const entries = [...unique.entries()];
  for (let i = 0; i < entries.length; i += 400) {
    const slice = entries.slice(i, i + 400);
    const refs = slice.map(([id]) => db.collection(COLLECTION).doc(id));
    const existing = await db.getAll(...refs);
    const batch = db.batch();
    slice.forEach(([, site], idx) => {
      const snap = existing[idx];
      if (snap.exists) updated += 1;
      else inserted += 1;
      batch.set(refs[idx], buildWebsiteLeadPatch(snap.exists ? snap.data() : undefined, site, now), { merge: true });
    });
    await batch.commit();
  }
  return { inserted, updated };
}

/**
 * A stored no-website lead whose business turns out to have a website after
 * all stops being a website lead. The document is kept, only re-labelled.
 */
export async function markWebsiteAvailable(site, website, { db = getFirestore(), now = new Date() } = {}) {
  const ref = db.collection(COLLECTION).doc(websiteLeadDocId(site));
  const snap = await ref.get();
  if (!snap.exists || snap.data().websiteStatus !== 'missing') return false;
  invalidateCategories(COLLECTION);
  await ref.set({ websiteStatus: 'available', website, websiteCheckedAt: now }, { merge: true });
  return true;
}

function docToWebsiteLead(doc) {
  const d = doc.data();
  const iso = (ts) => ts?.toDate?.()?.toISOString?.() || null;
  return {
    dbId: doc.id,
    id: d.externalId || doc.id,
    business: d.business,
    category: d.category,
    location: d.location,
    address: d.address || null,
    phone: d.phone || null,
    website: null,
    mapsUrl: d.mapsUrl || null,
    rating: d.rating ?? null,
    totalReviews: d.totalReviews ?? null,
    hasWhatsApp: false,
    waLink: d.waLink || null,
    websiteStatus: d.websiteStatus || 'missing',
    leadTypes: d.leadTypes || [],
    badReview: { stars: 1, text: '', date: 'Unknown' },
    websiteCheckedAt: iso(d.websiteCheckedAt),
    savedAt: iso(d.createdAt || d.updatedAt),
  };
}

/** One page of confirmed no-website leads, newest first. */
export async function listWebsiteLeads({ limit, cursor, category, q } = {}) {
  return pagedList({
    db: getFirestore(),
    collection: COLLECTION,
    mapDoc: docToWebsiteLead,
    limit,
    cursor,
    category,
    q,
    where: [['websiteStatus', '==', 'missing']],
  });
}

export async function deleteWebsiteLead(leadId) {
  const ref = getFirestore().collection(COLLECTION).doc(leadId);
  const snap = await ref.get();
  if (!snap.exists) {
    const err = new Error('Website lead not found');
    err.status = 404;
    throw err;
  }
  invalidateCategories(COLLECTION);
  await ref.delete();
}

export async function deleteWebsiteLeadsByCategory(category) {
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

export const _COLLECTION = COLLECTION;
