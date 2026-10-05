/**
 * Discover publicly listed business emails from a website homepage and
 * common contact/about paths. Does not chase personal inboxes or login
 * walls — only addresses visible on public HTML.
 */

import * as cheerio from 'cheerio';
import { BUSINESS_EMAIL_PREFIXES, DISCOVERY_PATHS, EMAIL_SOURCES } from './constants.js';

const EMAIL_RE = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g;

const JUNK_LOCAL = new Set([
  'example',
  'email',
  'user',
  'name',
  'test',
  'noreply',
  'no-reply',
  'donotreply',
  'privacy',
  'legal',
  'webmaster',
  'postmaster',
  'abuse',
]);

const JUNK_DOMAINS = new Set([
  'example.com',
  'example.org',
  'sentry.io',
  'wixpress.com',
  'cloudflare.com',
  'schema.org',
  'w3.org',
  'googleapis.com',
  'gstatic.com',
  'google.com',
  'facebook.com',
  'instagram.com',
  'tiktok.com',
  'twitter.com',
  'x.com',
  'linkedin.com',
  'youtube.com',
  'placeholder.com',
  'yourdomain.com',
  'domain.com',
  'email.com',
]);

const FETCH_TIMEOUT_MS = 12000;
const MAX_HTML_BYTES = 1_500_000;

export function normalizeEmail(raw) {
  if (!raw) return null;
  let value = String(raw).trim().toLowerCase();
  value = value.replace(/^mailto:/i, '').split('?')[0].trim();
  value = value.replace(/[>,;]+$/g, '').replace(/^[<]+/g, '');
  if (!/^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$/.test(value)) return null;
  const [local, domain] = value.split('@');
  if (!local || !domain) return null;
  if (local.length > 64 || domain.length > 253) return null;
  if (JUNK_LOCAL.has(local)) return null;
  if (JUNK_DOMAINS.has(domain)) return null;
  if (domain.includes('..') || local.startsWith('.') || local.endsWith('.')) return null;
  if (/\.(png|jpe?g|gif|svg|webp|css|js)$/i.test(domain)) return null;
  return value;
}

export function extractEmailsFromHtml(html) {
  const found = [];
  const text = String(html || '');
  const matches = text.match(EMAIL_RE) || [];
  for (const m of matches) {
    const normalized = normalizeEmail(m);
    if (normalized) found.push({ email: normalized, via: 'text' });
  }

  try {
    const $ = cheerio.load(text);
    $('a[href^="mailto:"]').each((_, el) => {
      const href = $(el).attr('href') || '';
      const normalized = normalizeEmail(href);
      if (normalized) found.push({ email: normalized, via: 'mailto' });
    });
  } catch {
    // Cheerio parse failures still leave regex hits above.
  }

  return found;
}

export function scoreEmail(email, siteHost) {
  const [local, domain] = email.split('@');
  let score = 10;
  if (BUSINESS_EMAIL_PREFIXES.includes(local)) score += 40;
  if (siteHost && (domain === siteHost || domain.endsWith(`.${siteHost}`))) score += 25;
  if (local.includes('.')) score -= 8;
  if (/^\d+$/.test(local)) score -= 20;
  return score;
}

function sourceForPath(pathname, via) {
  if (via === 'mailto') return 'mailto';
  const p = (pathname || '/').toLowerCase();
  if (p.includes('contact')) return 'contact_page';
  if (p.includes('about')) return 'about_page';
  return 'website';
}

export function pickBestEmail(candidates, siteHost) {
  const byEmail = new Map();
  for (const c of candidates) {
    const prev = byEmail.get(c.email);
    const score = scoreEmail(c.email, siteHost) + (c.via === 'mailto' ? 5 : 0);
    if (!prev || score > prev.score) {
      byEmail.set(c.email, { ...c, score });
    }
  }
  const ranked = [...byEmail.values()].sort((a, b) => b.score - a.score);
  return { ranked, best: ranked[0] || null };
}

export function originFromWebsite(website) {
  if (!website) return null;
  try {
    const withProto = /^https?:\/\//i.test(website) ? website : `https://${website}`;
    const url = new URL(withProto);
    if (!url.hostname || url.hostname === 'localhost') return null;
    return `${url.protocol}//${url.host}`;
  } catch {
    return null;
  }
}

async function fetchHtml(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        'User-Agent': 'LeadFinderOutreach/1.0 (+https://localhost; website-quality review)',
        Accept: 'text/html,application/xhtml+xml',
      },
    });
    if (!res.ok) {
      return { ok: false, status: res.status, html: '', finalUrl: res.url };
    }
    const buf = Buffer.from(await res.arrayBuffer());
    const html = buf.subarray(0, MAX_HTML_BYTES).toString('utf8');
    return { ok: true, status: res.status, html, finalUrl: res.url };
  } catch (err) {
    return { ok: false, status: 0, html: '', error: err.message || String(err) };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @param {string|null} website
 * @returns {Promise<{
 *   emails: {email: string, source: string, score: number}[],
 *   primary: string|null,
 *   emailSource: string|null,
 *   pagesFetched: number,
 *   lastError: string|null,
 * }>}
 */
export async function discoverEmailsFromWebsite(website) {
  const origin = originFromWebsite(website);
  if (!origin) {
    return {
      emails: [],
      primary: null,
      emailSource: null,
      pagesFetched: 0,
      lastError: website ? 'Website URL is not a valid http(s) origin' : 'No website URL on this lead',
    };
  }

  let siteHost;
  try {
    siteHost = new URL(origin).hostname.replace(/^www\./, '');
  } catch {
    siteHost = null;
  }

  const candidates = [];
  let pagesFetched = 0;
  let lastError = null;

  for (const path of DISCOVERY_PATHS) {
    const url = path === '/' ? `${origin}/` : `${origin}${path}`;
    const result = await fetchHtml(url);
    if (!result.ok) {
      lastError = result.error || `HTTP ${result.status} fetching ${url}`;
      continue;
    }
    pagesFetched += 1;
    const extracted = extractEmailsFromHtml(result.html);
    let pathname = path;
    try {
      pathname = new URL(result.finalUrl || url).pathname;
    } catch {
      /* keep path */
    }
    for (const item of extracted) {
      candidates.push({
        email: item.email,
        source: sourceForPath(pathname, item.via),
        via: item.via,
      });
    }
  }

  const { ranked, best } = pickBestEmail(candidates, siteHost);
  const emails = ranked.map((r) => ({
    email: r.email,
    source: EMAIL_SOURCES.includes(r.source) ? r.source : 'website',
    score: r.score,
  }));

  return {
    emails,
    primary: best?.email || null,
    emailSource: best?.source || null,
    pagesFetched,
    lastError: emails.length ? null : lastError || (pagesFetched ? 'No public email found on crawled pages' : lastError),
  };
}
