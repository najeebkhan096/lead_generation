/**
 * Cursor pagination for the Jobs collections (the lead collections have their
 * own in lib/pagination.js, keyed on `updatedAt`; jobs sort on a field the
 * caller picks — "newest discovered" must not reshuffle when a job is
 * re-verified).
 *
 * Two paths, as in the lead pager:
 *   indexed  `where(equality…) + orderBy(sort, id) + startAfter + limit` — reads
 *            one page;
 *   scan     when a filter has no index, the server walks the collection in
 *            chunks (field-masked), keeps matches, and stops when a page is
 *            full or a per-request budget is spent; the response then carries
 *            a cursor and the client simply asks again.
 *
 * Request:  limit (default 25, max 100), cursor (opaque).
 * Response: { items, nextCursor, total }; `total` is only known on the indexed
 *           path's first page.
 */

import { docId, toMillis, isMissingIndex } from './firestoreUtil.js';

export const DEFAULT_PAGE = 25;
export const MAX_PAGE = 100;
const SCAN_CHUNK = 400;
const SCAN_BUDGET = 3000;

export function pageSize(raw) {
  const n = Math.floor(Number(raw));
  if (!Number.isFinite(n) || n < 1) return DEFAULT_PAGE;
  return Math.min(n, MAX_PAGE);
}

export function encodeCursor(sortValue, id) {
  return Buffer.from(JSON.stringify({ v: toMillis(sortValue) ?? 0, i: id })).toString('base64url');
}

export function decodeCursor(cursor) {
  if (!cursor) return null;
  try {
    const { v, i } = JSON.parse(Buffer.from(String(cursor), 'base64url').toString('utf8'));
    if (typeof v !== 'number' || typeof i !== 'string' || !i) throw new Error('shape');
    return { ms: v, id: i };
  } catch {
    const err = new Error('Invalid cursor');
    err.status = 400;
    throw err;
  }
}

/**
 * @param {object} o
 * @param {*} o.db
 * @param {string} o.collection
 * @param {Array<[string,string,*]>} [o.where]      index-backed equality / array-contains filters
 * @param {string} o.sortField                      a Date field present on every document
 * @param {'asc'|'desc'} [o.direction]
 * @param {number} [o.limit]
 * @param {string} [o.cursor]
 * @param {(data: object) => boolean} [o.memoryFilter]  filter without an index (forces the scan path)
 * @param {string[]} [o.scanFields]                 fields memoryFilter reads (field mask)
 * @param {(snap) => object} o.mapDoc
 */
export async function pagedQuery({ db, collection, where = [], sortField, direction = 'desc', limit, cursor, memoryFilter, scanFields = [], mapDoc, scanBudget = SCAN_BUDGET }) {
  const size = pageSize(limit);
  const start = decodeCursor(cursor);

  const base = () => where.reduce((q, [f, op, v]) => q.where(f, op, v), db.collection(collection));
  const ordered = (q) => q.orderBy(sortField, direction).orderBy(docId(), direction);
  const after = (q) => (start ? q.startAfter(new Date(start.ms), start.id) : q);
  const sortOf = (snap) => snap.get(sortField);

  if (!memoryFilter) {
    const totalPromise = start
      ? Promise.resolve(null)
      : base()
          .count()
          .get()
          .then((s) => s.data().count)
          .catch(() => null); // a nicety; the page is what matters
    const docs = (await after(ordered(base())).limit(size + 1).get()).docs;
    const total = await totalPromise;
    const page = docs.slice(0, size);
    return {
      items: page.map(mapDoc),
      nextCursor: docs.length > size ? encodeCursor(sortOf(page[page.length - 1]), page[page.length - 1].id) : null,
      total,
    };
  }

  const fields = [...new Set([sortField, ...scanFields, ...where.map(([f]) => f)])];
  const matches = [];
  let last = start;
  let lastDoc = null;
  let scanned = 0;
  let exhausted = false;

  while (matches.length < size && scanned < scanBudget) {
    let q = ordered(base()).select(...fields).limit(SCAN_CHUNK);
    if (last) q = q.startAfter(new Date(last.ms), last.id);
    const chunk = (await q.get()).docs;
    if (!chunk.length) {
      exhausted = true;
      break;
    }
    for (const doc of chunk) {
      scanned += 1;
      if (memoryFilter(doc.data())) {
        matches.push(doc);
        if (matches.length >= size) {
          // Resume right after the last match; the rest of this chunk is re-read next time.
          return { items: await hydrate(db, matches, mapDoc), nextCursor: encodeCursor(sortOf(doc), doc.id), total: null, scanned };
        }
      }
      lastDoc = doc;
    }
    last = { ms: toMillis(sortOf(lastDoc)) ?? 0, id: lastDoc.id };
    if (chunk.length < SCAN_CHUNK) {
      exhausted = true;
      break;
    }
  }
  return {
    items: await hydrate(db, matches, mapDoc),
    nextCursor: exhausted || !lastDoc ? null : encodeCursor(sortOf(lastDoc), lastDoc.id),
    total: null,
    scanned,
  };
}

async function hydrate(db, docs, mapDoc) {
  if (!docs.length) return [];
  const full = await db.getAll(...docs.map((d) => d.ref));
  return full.filter((d) => d.exists).map(mapDoc);
}

/**
 * Runs [attempt] with the index-backed plan; if Firestore says the index is
 * still building, retries with no server-side filters (everything in memory).
 */
export async function withIndexFallback(attempt, fallback) {
  try {
    return await attempt();
  } catch (err) {
    if (isMissingIndex(err)) return fallback();
    throw err;
  }
}
