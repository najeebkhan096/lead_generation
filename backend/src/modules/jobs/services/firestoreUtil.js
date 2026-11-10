/** Small helpers shared by the Jobs stores. */

import { FieldPath } from 'firebase-admin/firestore';

/** A JS Date from a Firestore Timestamp, a Date, an ISO string or epoch ms; else null. */
export function toDate(value) {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  const d = new Date(value);
  return Number.isFinite(d.getTime()) ? d : null;
}

export const toMillis = (value) => toDate(value)?.getTime() ?? null;

/** Firestore rejects `undefined`; the module stores `null` for "unknown" instead. */
export function stripUndefined(value) {
  if (Array.isArray(value)) return value.map(stripUndefined);
  if (value instanceof Date || value === null || typeof value !== 'object') return value === undefined ? null : value;
  const out = {};
  for (const [k, v] of Object.entries(value)) if (v !== undefined) out[k] = stripUndefined(v);
  return out;
}

/** Dates -> ISO strings (recursively) for JSON responses. */
export function serialize(value) {
  if (value == null) return value;
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, serialize(v)]));
  return value;
}

export function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

/** getAll in slices (the SDK is happiest with a few hundred refs per call). */
export async function getAllChunked(db, refs, size = 300) {
  const out = [];
  for (const slice of chunk(refs, size)) out.push(...(await db.getAll(...slice)));
  return out;
}

/** Commits [ops] ((batch) => void) in batches of at most [size] writes. */
export async function commitInBatches(db, items, apply, size = 400) {
  for (const slice of chunk(items, size)) {
    const batch = db.batch();
    slice.forEach((item) => apply(batch, item));
    await batch.commit();
  }
}

export const docId = () => FieldPath.documentId();

export const isAlreadyExists = (err) => err?.code === 6 || /ALREADY_EXISTS/i.test(String(err?.message || ''));
export const isMissingIndex = (err) => err?.code === 9 || /requires an index|FAILED_PRECONDITION/i.test(String(err?.message || ''));
