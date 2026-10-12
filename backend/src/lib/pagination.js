/**
 * Cursor pagination for the lead collections.
 *
 * `leads`, `websiteLeads`, `whatsappLeads` and `emailLeads` are all listed
 * newest-first, and one of them (`websiteLeads`) holds tens of thousands of
 * documents — nothing here ever loads a whole collection into a response.
 *
 * Request:  `limit` (default 50, max 200), `cursor` (opaque, from the
 *           previous response), `category` (exact), `q` (search text).
 * Response: `{ leads, nextCursor, total }` — `nextCursor` is `null` on the
 *           last page; `total` is the number of documents matching the
 *           filters, or `null` while a text search makes that unknowable
 *           without scanning everything.
 *
 * Two execution paths:
 *
 *  1. **Indexed** (no text search, no in-memory filter): a straight
 *     `where(category) + orderBy + startAfter + limit` query. Reads exactly
 *     one page of documents.
 *  2. **Scan** (text search or an in-memory filter): Firestore has no
 *     substring search, so the server walks the collection in chunks
 *     (newest first), keeps the matches, and stops as soon as a page is
 *     full. The scan is bounded per request ([SCAN_BUDGET]); when the
 *     budget runs out the response carries a cursor and the client simply
 *     asks again. Only the server reads the non-matching documents — they
 *     never reach the browser.
 */

import { FieldPath, Timestamp } from 'firebase-admin/firestore';

export const DEFAULT_PAGE_SIZE = 50;
export const MAX_PAGE_SIZE = 200;
const SCAN_CHUNK = 500;
// Per request. Kept modest so each response returns quickly; the client
// keeps asking (with the cursor) while a search is still running.
const SCAN_BUDGET = 2500;

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

export function parsePageSize(raw) {
  const n = Math.floor(Number(raw));
  if (!Number.isFinite(n) || n < 1) return DEFAULT_PAGE_SIZE;
  return Math.min(n, MAX_PAGE_SIZE);
}

/** A cursor is the last returned document's `updatedAt` and id. */
export function encodeCursor(doc) {
  const updatedAt = doc.get('updatedAt');
  const ms = updatedAt?.toMillis?.() ?? 0;
  return Buffer.from(JSON.stringify({ m: ms, i: doc.id })).toString('base64url');
}

export function decodeCursor(cursor) {
  if (!cursor) return null;
  try {
    const { m, i } = JSON.parse(Buffer.from(String(cursor), 'base64url').toString('utf8'));
    if (typeof m !== 'number' || typeof i !== 'string' || !i) throw new Error('bad shape');
    return { ms: m, id: i };
  } catch {
    throw httpError(400, 'Invalid cursor');
  }
}

function normalize(text) {
  return String(text ?? '').toLowerCase();
}

/**
 * Builds the text matcher for `q`: every whitespace-separated word must
 * appear in at least one of `fields`. Digit-only words also match against
 * a field's digits, so "5125550" finds "+1 (512) 555-0142".
 */
export function buildMatcher(q, fields) {
  const words = normalize(q).split(/\s+/).filter(Boolean);
  if (!words.length) return null;
  return (data) => {
    const values = fields.map((f) => normalize(data[f]));
    const digits = values.map((v) => v.replace(/\D/g, ''));
    return words.every((w) => {
      const onlyDigits = /^\d+$/.test(w);
      return values.some((v, i) => v.includes(w) || (onlyDigits && digits[i].includes(w)));
    });
  };
}

function isMissingIndex(err) {
  return err?.code === 9 || /requires an index|FAILED_PRECONDITION/i.test(String(err?.message || ''));
}

/**
 * @param {object} opts
 * @param {FirebaseFirestore.Firestore} opts.db
 * @param {string} opts.collection
 * @param {(doc) => object} opts.mapDoc - snapshot -> API shape
 * @param {number} [opts.limit]
 * @param {string} [opts.cursor]
 * @param {string} [opts.category] - exact category (server-side where)
 * @param {string} [opts.q] - text search over [opts.searchFields]
 * @param {string[]} [opts.searchFields]
 * @param {Array<[string, string, any]>} [opts.where] - extra equality filters
 * @param {(data: object) => boolean} [opts.memoryFilter] - extra filter that
 *   has no index; forces the scan path
 * @param {string[]} [opts.maskFields] - fields `memoryFilter` reads, so the
 *   scan's field mask includes them
 */
export async function pagedList({
  db,
  collection,
  mapDoc,
  limit,
  cursor,
  category,
  q,
  searchFields = ['business', 'phone', 'address', 'location', 'category', 'email'],
  where = [],
  memoryFilter,
  maskFields = [],
}) {
  const size = parsePageSize(limit);
  const start = decodeCursor(cursor);
  const matcher = buildMatcher(q, searchFields);
  const wantsScan = Boolean(matcher || memoryFilter);

  const filtered = (useCategory) => {
    let base = db.collection(collection);
    if (useCategory && category) base = base.where('category', '==', category);
    for (const [field, op, value] of where) base = base.where(field, op, value);
    return base;
  };
  const ordered = (base) => base.orderBy('updatedAt', 'desc').orderBy(FieldPath.documentId(), 'desc');
  const after = (query) =>
    start ? query.startAfter(Timestamp.fromMillis(start.ms), start.id) : query;

  const run = async (useCategory) => {
    const inMemoryCategory = category && !useCategory ? (data) => data.category === category : null;

    if (!wantsScan && !inMemoryCategory) {
      // ---- indexed path: one page, plus one extra doc to know if more exist.
      // The total is only computed for the first page (the client keeps it),
      // and in parallel — it's an aggregation over the whole filter.
      const totalPromise = start
        ? Promise.resolve(null)
        : filtered(useCategory)
            .count()
            .get()
            .then((snap) => snap.data().count)
            .catch(() => null); // a nicety; the page itself is what matters
      const docs = (await after(ordered(filtered(useCategory))).limit(size + 1).get()).docs;
      const total = await totalPromise;
      const hasMore = docs.length > size;
      const page = docs.slice(0, size);
      return {
        leads: page.map(mapDoc),
        nextCursor: hasMore ? encodeCursor(page[page.length - 1]) : null,
        total,
      };
    }

    // ---- scan path. Chunks are read with a field mask (only what the
    // filters look at); the matches are re-read in full at the end, so a
    // search over thousands of documents doesn't drag every document's
    // whole body (reviews, links…) across the wire.
    const scanFields = [
      ...new Set(['updatedAt', 'category', ...searchFields, ...maskFields, ...where.map(([f]) => f)]),
    ];
    const hydrate = async (docs) => {
      if (!docs.length) return [];
      const full = await db.getAll(...docs.map((d) => d.ref));
      return full.filter((d) => d.exists).map(mapDoc);
    };
    const matches = [];
    let last = start;
    let lastDoc = null;
    let scanned = 0;
    let exhausted = false;

    while (matches.length < size && scanned < SCAN_BUDGET) {
      let query = ordered(filtered(useCategory)).select(...scanFields).limit(SCAN_CHUNK);
      if (last) query = query.startAfter(Timestamp.fromMillis(last.ms), last.id);
      const chunk = (await query.get()).docs;
      if (!chunk.length) {
        exhausted = true;
        break;
      }
      for (const doc of chunk) {
        scanned += 1;
        const data = doc.data();
        const ok =
          (!inMemoryCategory || inMemoryCategory(data)) &&
          (!matcher || matcher(data)) &&
          (!memoryFilter || memoryFilter(data));
        if (ok) {
          matches.push(doc);
          if (matches.length >= size) {
            // Resume right after the last match: the rest of this chunk is
            // re-read next time rather than skipped.
            return { leads: await hydrate(matches), nextCursor: encodeCursor(doc), total: null, scanned };
          }
        }
        lastDoc = doc;
      }
      last = { ms: lastDoc.get('updatedAt')?.toMillis?.() ?? 0, id: lastDoc.id };
      if (chunk.length < SCAN_CHUNK) {
        exhausted = true;
        break;
      }
    }

    return {
      leads: await hydrate(matches),
      // Budget spent but not exhausted: the client keeps going from here.
      nextCursor: exhausted || !lastDoc ? null : encodeCursor(lastDoc),
      total: null,
      scanned,
    };
  };

  try {
    return { ...(await run(true)), provider: 'firebase' };
  } catch (err) {
    // A category filter needs a composite index; while one is still
    // building, fall back to filtering by category in memory instead of
    // failing the page.
    if (category && isMissingIndex(err)) {
      return { ...(await run(false)), provider: 'firebase' };
    }
    throw err;
  }
}

// ---------------------------------------------------------------- categories

const CATEGORY_TTL_MS = 10 * 60 * 1000;
const categoryCache = new Map(); // collection -> { at, value }

/**
 * Distinct categories of a collection with their counts, biggest first.
 *
 * Firestore has no DISTINCT, so this reads one field per document — cached
 * for [CATEGORY_TTL_MS] so opening a page costs a scan at most every few
 * minutes, not on every visit. Deleting leads should call
 * [invalidateCategories].
 */
export async function listCategories(db, collection, { force = false } = {}) {
  const hit = categoryCache.get(collection);
  if (!force && hit && Date.now() - hit.at < CATEGORY_TTL_MS) return hit.value;

  const counts = new Map();
  let last = null;
  for (;;) {
    let query = db
      .collection(collection)
      .orderBy(FieldPath.documentId())
      .select('category')
      .limit(2000);
    if (last) query = query.startAfter(last);
    const snap = await query.get();
    if (!snap.docs.length) break;
    for (const doc of snap.docs) {
      const name = String(doc.get('category') || '').trim();
      if (name) counts.set(name, (counts.get(name) || 0) + 1);
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < 2000) break;
  }

  const value = [...counts.entries()]
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  categoryCache.set(collection, { at: Date.now(), value });
  return value;
}

export function invalidateCategories(collection) {
  if (collection) categoryCache.delete(collection);
  else categoryCache.clear();
}
