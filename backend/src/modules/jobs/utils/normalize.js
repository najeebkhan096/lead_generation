/**
 * Normalization and fingerprinting — the basis of duplicate detection.
 *
 * Two postings are "the same job" when they share (in priority order):
 *   1. a source job id on the same source,
 *   2. the same direct application URL (canonicalised),
 *   3. the same fingerprint = company + title + location,
 *   4. the same company + title with a near-identical description and a
 *      compatible location (MinHash similarity).
 */

import crypto from 'node:crypto';
import { fold } from './text.js';

const sha = (text, len = 40) => crypto.createHash('sha256').update(text).digest('hex').slice(0, len);

// ---------------------------------------------------------------- company

/** Legal-form words that don't identify a company ("Acme Inc." == "Acme"). */
const COMPANY_SUFFIXES = new Set([
  'inc', 'incorporated', 'llc', 'ltd', 'limited', 'gmbh', 'ag', 'co', 'corp', 'corporation', 'company',
  'plc', 'pjsc', 'llp', 'lp', 'sa', 'sas', 'bv', 'nv', 'pte', 'pvt', 'wll', 'fze', 'fzco', 'fzc', 'dmcc',
  'ug', 'kg', 'se', 'srl', 'spa', 'oy', 'ab', 'aps', 'kk', 'qsc', 'qpsc', 'qcsc', 'psc', 'and',
]);

export function companyKey(name) {
  const tokens = fold(name).replace(/\./g, '').split(' ').filter(Boolean);
  const kept = [...tokens];
  while (kept.length > 1 && COMPANY_SUFFIXES.has(kept[kept.length - 1])) kept.pop();
  return kept.join(' ') || tokens.join(' ');
}

// ------------------------------------------------------------------ title

const TITLE_NOISE = /\((?:[^)]*\b(?:m\s*\/\s*[fwdx]|f\s*\/\s*[mwdx]|w\s*\/\s*[mfdx]|d\s*\/\s*[mfwx]|all genders|gn|remote|hybrid|on-?site|full[- ]?time|part[- ]?time|contract|urgent|immediate)\b[^)]*)\)|\[[^\]]*\]/gi;
const TITLE_TAIL = /\s[-–—|:]\s*(?:remote|hybrid|on-?site|full[- ]?time|part[- ]?time|contract|urgent|immediate start)\s*$/i;

export function titleKey(title) {
  let t = String(title ?? '');
  t = t.replace(TITLE_NOISE, ' ').replace(TITLE_TAIL, '');
  t = fold(t)
    .replace(/\bsr\b/g, 'senior')
    .replace(/\bjr\b/g, 'junior')
    .replace(/\bdev\b/g, 'developer')
    .replace(/\bswe\b/g, 'software engineer')
    .replace(/\s+/g, ' ')
    .trim();
  return t;
}

// ----------------------------------------------------------------- location

/**
 * The location part of the fingerprint: country + city. State is left out
 * on purpose — sources spell it as "CA", "California" or not at all.
 * A remote job without a city is "remote" within its country (or worldwide).
 */
export function locationKey({ countryCode, city, workArrangement } = {}) {
  const cc = String(countryCode || '').toLowerCase() || 'xx';
  const c = fold(city);
  if (c) return `${cc}|${c}`;
  if (workArrangement === 'remote') return `${cc}|remote`;
  return `${cc}|`;
}

export function fingerprintOf(job) {
  const key = `${companyKey(job.companyName)}|${titleKey(job.title)}|${locationKey(job)}`;
  return sha(key);
}

// ---------------------------------------------------------------------- URL

const TRACKING_PARAMS = /^(utm_|mc_|ga_|hsa_)|^(gclid|fbclid|msclkid|yclid|dclid|ref|referrer|referer|src|source|trk|trackingid|tracking_id|campaign|cid|sid|lever-source|lever-origin|gh_src|jr_id|jobboard|jb|rx_|vs|s)$/i;

/** Hosts that only relay a posting; their URLs never identify the posting itself. */
const AGGREGATOR_HOSTS = /(^|\.)(adzuna\.[a-z.]+|jooble\.org|remotive\.(com|io)|indeed\.[a-z.]+|linkedin\.com|glassdoor\.[a-z.]+|ziprecruiter\.[a-z.]+|monster\.[a-z.]+|careerjet\.[a-z.]+|simplyhired\.[a-z.]+|jobrapido\.[a-z.]+|talent\.com|neuvoo\.[a-z.]+|bayt\.com|naukrigulf\.com|gulftalent\.com|learn4good\.com)$/i;

export function isAggregatorUrl(url) {
  try {
    return AGGREGATOR_HOSTS.test(new URL(url).hostname);
  } catch {
    return false;
  }
}

/**
 * The URL with tracking noise removed, or null when it isn't a usable
 * http(s) address. Stable under reordering of query parameters.
 */
export function canonicalUrl(raw) {
  if (!raw || typeof raw !== 'string') return null;
  let u;
  try {
    u = new URL(raw.trim());
  } catch {
    return null;
  }
  if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
  u.protocol = 'https:';
  u.hash = '';
  u.hostname = u.hostname.toLowerCase().replace(/^www\./, '');
  if (u.port === '80' || u.port === '443') u.port = '';
  const kept = [...u.searchParams.entries()].filter(([k]) => !TRACKING_PARAMS.test(k));
  kept.sort(([a], [b]) => a.localeCompare(b));
  u.search = '';
  for (const [k, v] of kept) u.searchParams.append(k, v);
  let path = u.pathname.replace(/\/index\.(html?|php)$/i, '/');
  if (path.length > 1) path = path.replace(/\/+$/, '');
  u.pathname = path;
  return u.toString();
}

/** The canonical *application* URL used as a duplicate key, or null if it's only an aggregator link. */
export function applyUrlKey(url) {
  const canon = canonicalUrl(url);
  if (!canon || isAggregatorUrl(canon)) return null;
  return canon;
}

// ------------------------------------------------------- description similarity

const SIGNATURE_SIZE = 32;
const SHINGLE = 5;
const MIN_WORDS_FOR_SIGNATURE = 40;
const SEEDS = Array.from({ length: SIGNATURE_SIZE }, (_, i) => Math.imul(i + 1, 0x9e3779b1) >>> 0);

function fnv1a(text) {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

function mix(x) {
  x = Math.imul(x ^ (x >>> 16), 0x85ebca6b);
  x = Math.imul(x ^ (x >>> 13), 0xc2b2ae35);
  return (x ^ (x >>> 16)) >>> 0;
}

/**
 * MinHash signature of a description (32 ints), or null when the text is too
 * short for a similarity to mean anything.
 */
export function descriptionSignature(text) {
  const words = fold(text).split(' ').filter((w) => w.length > 1);
  if (words.length < MIN_WORDS_FOR_SIGNATURE) return null;
  const sig = new Array(SIGNATURE_SIZE).fill(0xffffffff);
  for (let i = 0; i + SHINGLE <= words.length; i++) {
    const base = fnv1a(words.slice(i, i + SHINGLE).join(' '));
    for (let k = 0; k < SIGNATURE_SIZE; k++) {
      const v = mix(base ^ SEEDS[k]);
      if (v < sig[k]) sig[k] = v;
    }
  }
  return sig;
}

/** Estimated Jaccard similarity of two signatures (0..1), or 0 when either is missing. */
export function signatureSimilarity(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || !a.length) return 0;
  let same = 0;
  for (let i = 0; i < a.length; i++) if (a[i] === b[i]) same += 1;
  return same / a.length;
}

export const SIMILARITY_THRESHOLD = 0.8;

/**
 * Could two postings with the same company+title be the same opening, going
 * by where they are? Unknown parts are compatible; known and different are not.
 */
export function locationsCompatible(a, b) {
  const ca = String(a.countryCode || '').toUpperCase();
  const cb = String(b.countryCode || '').toUpperCase();
  if (ca && cb && ca !== cb) return false;
  const ra = a.workArrangement;
  const rb = b.workArrangement;
  if ((ra === 'remote' && rb === 'onsite') || (ra === 'onsite' && rb === 'remote')) return false;
  const cityA = fold(a.city);
  const cityB = fold(b.city);
  if (cityA && cityB) return cityA === cityB;
  const stA = fold(a.state);
  const stB = fold(b.state);
  if (stA && stB && stA !== stB) return false;
  return true;
}

// ---------------------------------------------------------------- doc ids

/** Document ids for the lookup collection. */
export function keyDocId(key) {
  return sha(key, 40);
}

export const sourceKey = (source, sourceJobId) => `s|${source}|${sourceJobId}`;
export const urlKey = (canon) => `u|${canon}`;
export const bucketKey = (job) => `ct|${companyKey(job.companyName)}|${titleKey(job.title)}`;

export { sha as hashText };
