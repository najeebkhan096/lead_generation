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
 *     scanModes: ['reviews'?, 'no_website'?]   which kinds of scan found it,
 *     createdAt, updatedAt
 *   }
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { leadDocId, normalizeCategory } from '../../lib/leadIdentity.js';
import { pagedList, invalidateCategories } from '../../lib/pagination.js';
import { _COLLECTIONS as RUN_COLLECTIONS } from '../scan/noWebsiteRunStore.js';

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
    // Every kind of scan that has found this business. Only a dedicated
    // no-website scan puts a lead in the no-website validation and lists.
    scanModes: unionList(existing?.scanModes, [site.scanMode === 'no_website' ? 'no_website' : 'reviews']),
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
    hasWhatsApp: d.hasWhatsApp === true,
    whatsAppCheckedAt: iso(d.whatsAppCheckedAt),
    waLink: d.waLink || null,
    email: d.email || null,
    emailStatus: d.emailStatus || null,
    emailFoundOn: d.emailFoundOn || null,
    emailCheckedAt: iso(d.emailCheckedAt),
    websiteStatus: d.websiteStatus || 'missing',
    leadTypes: d.leadTypes || [],
    badReview: { stars: 1, text: '', date: 'Unknown' },
    websiteCheckedAt: iso(d.websiteCheckedAt),
    savedAt: iso(d.createdAt || d.updatedAt),
  };
}

/**
 * One page of confirmed no-website leads, newest first.
 *
 * [scan] `no_website` keeps only the leads a dedicated no-website scan found
 * (see [inNoWebsiteScope]) — the 1-star scan also files the no-website
 * businesses it happens to open, and those are a different list. [verified]
 * keeps only the leads whose number a WhatsApp check confirmed; [withEmail] only
 * those an email lookup found an address for.
 */
export async function listWebsiteLeads({ limit, cursor, category, q, scan, verified, withEmail } = {}) {
  const where = [['websiteStatus', '==', 'missing']];
  if (verified) where.push(['hasWhatsApp', '==', true]);
  const runCategories = scan === 'no_website' ? await noWebsiteRunCategories() : null;
  const page = await pagedList({
    db: getFirestore(),
    collection: COLLECTION,
    mapDoc: docToWebsiteLead,
    limit,
    cursor,
    category,
    q,
    where,
    memoryFilter:
      runCategories || withEmail
        ? (d) => (!runCategories || inNoWebsiteScope(d, runCategories)) && (!withEmail || Boolean(d.email))
        : undefined,
    maskFields: ['scanModes', 'email'],
  });
  // A scoped list is read by scanning, which cannot count; the first page
  // still reports how many leads there are (a short-lived tally, not a read
  // of the whole collection per request).
  if (runCategories && page.total == null && !cursor && !String(q || '').trim()) {
    const rows = await listWebsiteScanCategories({ verified, withEmail });
    page.total = category ? (rows.find((r) => r.name === category)?.count ?? 0) : rows.reduce((sum, r) => sum + r.count, 0);
  }
  return page;
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

// ---- validation (WhatsApp + email) ----------------------------------------

// ---- which scan found a lead -----------------------------------------------

/**
 * The categories a dedicated no-website scan has run for, normalised the way
 * `websiteLeads` stores them ("Cafe" -> "Cafe USA"). Used only for leads filed
 * before `scanModes` existed, whose origin is otherwise unknown.
 */
let runCategoryCache = { at: 0, value: new Set() };
export async function noWebsiteRunCategories({ db = getFirestore(), now = Date.now() } = {}) {
  if (now - runCategoryCache.at < 60_000) return runCategoryCache.value;
  const snap = await db.collection(RUN_COLLECTIONS.PROGRESS).select('category').get();
  const value = new Set();
  for (const doc of snap.docs) {
    const raw = doc.get('category');
    if (!raw) continue;
    value.add(String(raw).trim());
    const tagged = normalizeCategory(raw, 'US');
    if (tagged) value.add(tagged);
  }
  runCategoryCache = { at: now, value };
  return value;
}

/**
 * Was this lead found by a dedicated no-website scan? A lead says so itself
 * (`scanModes`). One filed before that field existed counts only when its
 * category is one a no-website scan has run for. A lead only the 1-star scan
 * has found does not count, so the 1-star searches never show up as no-website
 * ones.
 */
export function inNoWebsiteScope(d, runCategories) {
  if (Array.isArray(d.scanModes)) return d.scanModes.includes('no_website');
  return runCategories.has(String(d.category || '').trim());
}

/** The state part of a location — "Austin, TX" -> "TX"; a bare "Texas" stays. */
export function stateOfLocation(location) {
  const loc = String(location || '').trim();
  if (!loc) return '';
  const comma = loc.lastIndexOf(',');
  return (comma >= 0 ? loc.slice(comma + 1) : loc).trim();
}

/** Does [location] belong to one of [states] (lower-cased set)? No set = all. */
export function locationInStates(location, wantedLower) {
  if (!wantedLower?.size) return true;
  const loc = String(location || '').trim().toLowerCase();
  if (!loc) return false;
  return wantedLower.has(loc) || wantedLower.has(stateOfLocation(location).toLowerCase());
}

function wantedStates(states) {
  const list = (Array.isArray(states) ? states : []).map((s) => String(s).trim().toLowerCase()).filter(Boolean);
  return list.length ? new Set(list) : null;
}

/** An email check that ended without an answer is retried on the next run. */
export function emailCheckIsDefinite(d) {
  return Boolean(d.emailCheckedAt) && d.emailStatus !== 'check_failed';
}

/** What a validator works on: the stored business, in the shape the jobs take. */
function toValidationLead(id, d) {
  return {
    id,
    dbId: id,
    business: d.business || 'Unknown',
    phone: d.phone || null,
    location: d.location || null,
    category: d.category || null,
    address: d.address || null,
    website: null,
    mapsUrl: d.mapsUrl || null,
    waLink: d.waLink || null,
    email: d.email || null,
    whatsAppCheckedAt: d.whatsAppCheckedAt || null,
    emailCheckedAt: d.emailCheckedAt || null,
    emailStatus: d.emailStatus || null,
    sourceType: 'website',
  };
}

/**
 * Every confirmed no-website lead that a dedicated no-website scan found,
 * optionally only those in an exact [category]. Validation and the no-website
 * lists work on these only: leads the 1-star scan filed on the side are not
 * part of them.
 */
async function allMissingDocs(category) {
  let query = getFirestore().collection(COLLECTION).where('websiteStatus', '==', 'missing');
  const wanted = String(category || '').trim();
  if (wanted) query = query.where('category', '==', wanted);
  const [docs, runCategories] = await Promise.all([query.get().then((snap) => snap.docs), noWebsiteRunCategories()]);
  return docs.filter((doc) => inNoWebsiteScope(doc.data(), runCategories));
}

/**
 * The searches of the no-website scans, with how many leads each has: what the
 * validation page and the verified list offer as categories. [verified] counts
 * only the leads confirmed on WhatsApp.
 */
const SCAN_COUNT_TTL_MS = 20_000;
const scanCountCache = new Map(); // flags -> { at, value }

export async function listWebsiteScanCategories({ verified = false, withEmail = false } = {}) {
  const key = `${verified ? 'v' : ''}${withEmail ? 'e' : ''}`;
  const hit = scanCountCache.get(key);
  if (hit && Date.now() - hit.at < SCAN_COUNT_TTL_MS) return hit.value;

  const docs = await allMissingDocs();
  const counts = new Map();
  for (const doc of docs) {
    const d = doc.data();
    if (verified && d.hasWhatsApp !== true) continue;
    if (withEmail && !d.email) continue;
    const name = String(d.category || '').trim();
    if (name) counts.set(name, (counts.get(name) || 0) + 1);
  }
  const value = [...counts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  scanCountCache.set(key, { at: Date.now(), value });
  return value;
}

/** No-website leads by Firestore id, in the shape the validation jobs take. */
export async function getWebsiteLeadsByIds(ids) {
  const unique = [...new Set((ids || []).map(String).filter(Boolean))];
  if (!unique.length) return [];
  const db = getFirestore();
  const snaps = await db.getAll(...unique.map((id) => db.collection(COLLECTION).doc(id)));
  return snaps.filter((s) => s.exists).map((s) => toValidationLead(s.id, s.data()));
}

/**
 * Every no-website lead with a phone that has not been checked for WhatsApp,
 * optionally limited to one [category] and to [states]. Reads the collection and filters here — a
 * lead that was never checked has no `whatsAppCheckedAt` field at all, which a
 * Firestore `== null` query does not match.
 */
export async function listUncheckedWhatsApp({ states, category, recheck = false } = {}) {
  const wanted = wantedStates(states);
  return (await allMissingDocs(category))
    .map((doc) => [doc.id, doc.data()])
    .filter(([, d]) => d.phone && (recheck || !d.whatsAppCheckedAt) && locationInStates(d.location, wanted))
    .map(([id, d]) => toValidationLead(id, d));
}

/**
 * Every no-website lead without an email, that has not been looked up yet (or
 * whose last lookup failed), optionally limited to [states].
 */
export async function listUncheckedEmail({ states, category, recheck = false } = {}) {
  const wanted = wantedStates(states);
  return (await allMissingDocs(category))
    .map((doc) => [doc.id, doc.data()])
    .filter(([, d]) => !d.email && d.business && (recheck || !emailCheckIsDefinite(d)) && locationInStates(d.location, wanted))
    .map(([id, d]) => toValidationLead(id, d));
}

/**
 * Per-state validation progress, for the state pickers: how many businesses
 * each state has, how many a check applies to, how many are checked, and how
 * many came out positive. `count` is what a run would work through.
 */
export function summarizeValidationRows(docs, kind) {
  const byState = new Map();
  for (const d of docs) {
    const name = stateOfLocation(d.location) || 'Unknown';
    const row = byState.get(name) || { name, total: 0, eligible: 0, checked: 0, found: 0 };
    row.total += 1;
    if (kind === 'whatsapp') {
      if (d.phone) {
        row.eligible += 1;
        if (d.whatsAppCheckedAt) row.checked += 1;
        if (d.hasWhatsApp === true) row.found += 1;
      }
    } else {
      row.eligible += 1;
      if (d.email) {
        row.checked += 1;
        row.found += 1;
      } else if (emailCheckIsDefinite(d)) {
        row.checked += 1;
      }
    }
    byState.set(name, row);
  }
  const locations = [...byState.values()]
    .map((row) => {
      const count = row.eligible - row.checked;
      const status = !row.eligible ? 'no_phone' : row.checked >= row.eligible ? 'validated' : row.checked === 0 ? 'not_validated' : 'partial';
      return { ...row, count, status };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
  return { total: locations.reduce((sum, l) => sum + l.count, 0), locations };
}

export async function summarizeWebsiteLeadValidation(kind, { category } = {}) {
  const docs = (await allMissingDocs(category)).map((d) => d.data());
  return summarizeValidationRows(docs, kind === 'email' ? 'email' : 'whatsapp');
}

/** Flags a no-website lead with the result of a real WhatsApp check. */
export async function updateWebsiteLeadWhatsApp(leadId, { hasWhatsApp }) {
  await getFirestore().collection(COLLECTION).doc(leadId).update({
    hasWhatsApp: Boolean(hasWhatsApp),
    whatsAppCheckedAt: FieldValue.serverTimestamp(),
    // Only a no-website scan's lead is ever validated, so say so on the lead
    // itself: that is what lets the phone ask for exactly these (and a lead filed
    // before `scanModes` existed gets its tag the first time it is checked).
    scanModes: FieldValue.arrayUnion('no_website'),
  });
}

/**
 * Records how an email lookup ended. A found address is stored on the lead
 * itself; "not found" and "failed" only stamp the check, so an address that was
 * already stored is never erased by a later miss.
 */
export async function updateWebsiteLeadEmail(leadId, { status, email = null, emails = [], source = null, foundOn = null }) {
  const patch = { emailStatus: status, emailCheckedAt: FieldValue.serverTimestamp() };
  if (status === 'found' && email) {
    patch.email = email;
    patch.emails = emails;
    if (source) patch.emailSource = source;
    if (foundOn) patch.emailFoundOn = foundOn;
  }
  await getFirestore().collection(COLLECTION).doc(leadId).set(patch, { merge: true });
}

/**
 * Tags the already-validated no-website leads that were filed before `scanModes`
 * existed, so the phone can ask for exactly the no-website scan's leads.
 *
 * A validated lead (`hasWhatsApp`) with no `scanModes` gets `['no_website']`
 * when its category is one a no-website scan has run for (see
 * [inNoWebsiteScope]). Anything else is left alone, untagged: it is a lead a
 * 1-star scan filed on the side, and it stays out of the no-website lists.
 * Only `scanModes` is written, and only on those documents.
 *
 * @returns {Promise<{validated: number, tagged: number, left: {category: string, count: number}[]}>}
 */
export async function tagVerifiedNoWebsiteLeads({ apply = false, db = getFirestore() } = {}) {
  const runCategories = await noWebsiteRunCategories({ db, now: Date.now() + 61_000 });
  const snap = await db
    .collection(COLLECTION)
    .where('websiteStatus', '==', 'missing')
    .where('hasWhatsApp', '==', true)
    .get();
  const toTag = [];
  const left = new Map();
  for (const doc of snap.docs) {
    const d = doc.data();
    if (Array.isArray(d.scanModes)) continue; // already knows where it came from
    if (inNoWebsiteScope(d, runCategories)) toTag.push(doc.ref);
    else left.set(d.category || '(none)', (left.get(d.category || '(none)') || 0) + 1);
  }
  if (apply) {
    for (let i = 0; i < toTag.length; i += 400) {
      const batch = db.batch();
      for (const ref of toTag.slice(i, i + 400)) batch.update(ref, { scanModes: FieldValue.arrayUnion('no_website') });
      await batch.commit();
    }
  }
  return {
    validated: snap.size,
    tagged: toTag.length,
    left: [...left.entries()].map(([category, count]) => ({ category, count })).sort((a, b) => b.count - a.count),
  };
}

/** Test seam: forgets the short-lived tallies and the no-website scans' categories. */
export function _resetScopeCaches() {
  runCategoryCache = { at: 0, value: new Set() };
  scanCountCache.clear();
}

export const _COLLECTION = COLLECTION;
