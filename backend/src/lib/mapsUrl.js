/**
 * Google Maps link handling for client businesses.
 *
 * A client is stored as just a business name and the link to its Google
 * Maps listing. People paste these from the Maps app, so links often lack
 * the scheme ("maps.app.goo.gl/abc") and sometimes are not links at all.
 */

const GOOGLE_HOST = /(^|\.)google\.[a-z.]{2,}$/i;
const GOOGLE_SHORT_HOSTS = new Set(['goo.gl', 'maps.app.goo.gl', 'g.page', 'g.co', 'share.google']);

function isGoogleHost(hostname) {
  const host = hostname.toLowerCase();
  return GOOGLE_HOST.test(host) || GOOGLE_SHORT_HOSTS.has(host);
}

/**
 * Returns a clean https URL for a Google Maps listing, or null when [raw] is
 * not a Google link. Adds a missing scheme; never invents or rewrites the
 * path or query.
 */
export function normalizeMapsUrl(raw) {
  if (typeof raw !== 'string') return null;
  const text = raw.trim();
  if (!text || /\s/.test(text)) return null;
  const withScheme = /^https?:\/\//i.test(text) ? text : `https://${text}`;
  let url;
  try {
    url = new URL(withScheme);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (!url.hostname.includes('.')) return null;
  if (!isGoogleHost(url.hostname)) return null;
  // "https://google.com" alone is a website, not a listing.
  if (url.pathname === '/' && !url.search && !url.hash) return null;
  url.protocol = 'https:';
  return url.toString();
}

/** Lowercased, whitespace-collapsed name used to spot the same business. */
export function clientNameKey(name) {
  return String(name || '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}
