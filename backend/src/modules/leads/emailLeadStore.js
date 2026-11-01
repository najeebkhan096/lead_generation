/**
 * Email leads — businesses with a website whose website publishes a business
 * email address — in their own Firestore collection, `emailLeads`.
 *
 * Only addresses that were actually found are stored. How every check ended
 * (found / not_found / check_failed / not_checked) is remembered in
 * `leadChecks` (validation/leadChecks.js), so a miss or a failure never makes
 * a document, and never touches one that exists.
 *
 *   emailLeads/{id} = {
 *     business, category, location, address, phone, mapsUrl, rating, ...,
 *     website, websiteStatus: 'available',
 *     emailStatus: 'found',
 *     emails: [{ address, sourceUrl, foundAt }],   // every address, in order
 *     email, emailSourceUrl,                       // the first one, for lists/search
 *     emailCheckedAt,                              // last time a check FOUND something
 *     lastCheckStatus, lastCheckReason, lastCheckAt, // how the latest check ended
 *     leadTypes: ['email', 'review'?], createdAt, updatedAt
 *   }
 */

import { getFirestore } from '../../firebase/admin.js';
import { leadDocId } from '../../lib/leadIdentity.js';
import { pagedList, invalidateCategories } from '../../lib/pagination.js';
import { businessFields, unionList } from './websiteLeadStore.js';

const COLLECTION = 'emailLeads';
const MAX_STORED_EMAILS = 10;

/** Same id the business has in every other lead collection. */
export const emailLeadDocId = leadDocId;

/**
 * Merges the addresses a check found into those already stored. An address
 * keeps the source page it was first seen on; new ones are appended.
 */
export function mergeEmails(existing, found, foundAt) {
  const out = [];
  const seen = new Set();
  for (const e of [...(Array.isArray(existing) ? existing : []), ...found.map((f) => ({ ...f, foundAt }))]) {
    const address = String(e?.address || '').toLowerCase();
    if (!address || seen.has(address)) continue;
    seen.add(address);
    out.push({ address, sourceUrl: e.sourceUrl || null, foundAt: e.foundAt || foundAt });
  }
  return out.slice(0, MAX_STORED_EMAILS);
}

/**
 * What to write after a check. Pure: [existing] is the stored data or
 * undefined; the result is a merge patch, or `null` when nothing should be
 * written (a check that found nothing, for a business with no document).
 *
 * The rule that protects data: stored addresses are only ever added to. A
 * later check that finds nothing — or fails — records how it ended and leaves
 * `emails` / `email` exactly as they were.
 */
export function buildEmailLeadPatch(existing, site, result, now = new Date()) {
  const nowIso = now.toISOString();
  if (result.status !== 'found') {
    if (!existing) return null;
    return { lastCheckStatus: result.status, lastCheckReason: result.reason ?? null, lastCheckAt: now };
  }
  const emails = mergeEmails(existing?.emails, result.emails, nowIso);
  const patch = {
    ...businessFields(site),
    business: site.business || existing?.business || 'Unknown',
    website: result.website || site.website,
    websiteStatus: 'available',
    emailStatus: 'found',
    emails,
    email: emails[0].address,
    emailSourceUrl: emails[0].sourceUrl,
    emailCheckedAt: now,
    lastCheckStatus: 'found',
    lastCheckReason: null,
    lastCheckAt: now,
    leadTypes: unionList(existing?.leadTypes, ['email', ...(site.leadTypes || [])]),
    updatedAt: now,
  };
  if (!existing) patch.createdAt = now;
  return patch;
}

/**
 * Writes the outcome of one email check.
 * @returns {Promise<'inserted'|'updated'|'unchanged'>}
 */
export async function saveEmailResult(site, result, { db = getFirestore(), now = new Date() } = {}) {
  const ref = db.collection(COLLECTION).doc(emailLeadDocId(site));
  const snap = await ref.get();
  const patch = buildEmailLeadPatch(snap.exists ? snap.data() : undefined, site, result, now);
  if (!patch) return 'unchanged';
  invalidateCategories(COLLECTION);
  await ref.set(patch, { merge: true });
  return snap.exists ? 'updated' : 'inserted';
}

function docToEmailLead(doc) {
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
    website: d.website || null,
    mapsUrl: d.mapsUrl || null,
    rating: d.rating ?? null,
    totalReviews: d.totalReviews ?? null,
    hasWhatsApp: false,
    waLink: d.waLink || null,
    email: d.email || null,
    emails: (d.emails || []).map((e) => ({ address: e.address, sourceUrl: e.sourceUrl || null, foundAt: e.foundAt || null })),
    emailSourceUrl: d.emailSourceUrl || null,
    emailStatus: d.emailStatus || 'found',
    lastCheckStatus: d.lastCheckStatus || null,
    leadTypes: d.leadTypes || [],
    badReview: { stars: 1, text: '', date: 'Unknown' },
    emailCheckedAt: iso(d.emailCheckedAt),
    savedAt: iso(d.createdAt || d.updatedAt),
  };
}

/** One page of leads with a found email, newest first. */
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
  const ref = getFirestore().collection(COLLECTION).doc(leadId);
  const snap = await ref.get();
  if (!snap.exists) {
    const err = new Error('Email lead not found');
    err.status = 404;
    throw err;
  }
  invalidateCategories(COLLECTION);
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

export const _COLLECTION = COLLECTION;
