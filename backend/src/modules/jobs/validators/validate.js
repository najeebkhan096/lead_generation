/**
 * Tiny validation toolkit (the project has no schema library and the module
 * needs none). Each helper reads a field, checks it, and records problems in
 * [Problems]; the caller throws one 422 listing everything wrong at once.
 */

import { invalid } from '../utils/errors.js';

export class Problems {
  constructor() {
    this.list = [];
  }
  add(field, message) {
    this.list.push({ field, message });
  }
  /** Problems reported through the returned object are filed under "prefix.field". */
  scope(prefix) {
    return { add: (field, message) => this.add(`${prefix}.${field}`, message) };
  }
  throwIfAny() {
    if (this.list.length) throw invalid('Validation failed', this.list);
  }
}

export function isObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export function str(p, body, field, { required = false, max = 200, min = 0, pattern, oneOf, fallback = null } = {}) {
  let v = body?.[field];
  if (v === undefined || v === null || v === '') {
    if (required) p.add(field, 'is required');
    return fallback;
  }
  if (typeof v !== 'string') {
    p.add(field, 'must be a string');
    return fallback;
  }
  v = v.trim();
  if (v.length < min) p.add(field, `must be at least ${min} characters`);
  if (v.length > max) p.add(field, `must be at most ${max} characters`);
  if (pattern && !pattern.test(v)) p.add(field, 'has an invalid format');
  if (oneOf && !oneOf.includes(v)) p.add(field, `must be one of: ${oneOf.join(', ')}`);
  return v;
}

export function num(p, body, field, { min = -Infinity, max = Infinity, integer = false, required = false, fallback = null } = {}) {
  const v = body?.[field];
  if (v === undefined || v === null || v === '') {
    if (required) p.add(field, 'is required');
    return fallback;
  }
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n)) {
    p.add(field, 'must be a number');
    return fallback;
  }
  if (integer && !Number.isInteger(n)) p.add(field, 'must be a whole number');
  if (n < min) p.add(field, `must be at least ${min}`);
  if (n > max) p.add(field, `must be at most ${max}`);
  return n;
}

export function bool(p, body, field, fallback = false) {
  const v = body?.[field];
  if (v === undefined || v === null) return fallback;
  if (typeof v === 'boolean') return v;
  if (v === 'true' || v === '1') return true;
  if (v === 'false' || v === '0') return false;
  p.add(field, 'must be true or false');
  return fallback;
}

export function strList(p, body, field, { max = 50, itemMax = 100, required = false } = {}) {
  const v = body?.[field];
  if (v === undefined || v === null) {
    if (required) p.add(field, 'is required');
    return [];
  }
  if (!Array.isArray(v)) {
    p.add(field, 'must be a list');
    return [];
  }
  if (v.length > max) p.add(field, `must have at most ${max} entries`);
  const out = [];
  v.slice(0, max).forEach((item, i) => {
    if (typeof item !== 'string' || !item.trim()) {
      p.add(`${field}[${i}]`, 'must be a non-empty string');
      return;
    }
    if (item.trim().length > itemMax) p.add(`${field}[${i}]`, `must be at most ${itemMax} characters`);
    out.push(item.trim());
  });
  if (required && !out.length) p.add(field, 'needs at least one entry');
  return out;
}

/** Query-string values arrive as strings; these coerce without throwing. */
export const q = {
  str: (query, key) => (typeof query[key] === 'string' && query[key].trim() ? query[key].trim() : undefined),
  int: (query, key) => {
    const n = Number(query[key]);
    return Number.isFinite(n) && query[key] !== '' ? Math.trunc(n) : undefined;
  },
  list: (query, key) => {
    const raw = query[key];
    const parts = Array.isArray(raw) ? raw : typeof raw === 'string' ? raw.split(',') : [];
    const out = parts.map((s) => String(s).trim()).filter(Boolean);
    return out.length ? out : undefined;
  },
};
