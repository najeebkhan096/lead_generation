/**
 * Visits a business's website and collects the email addresses it publishes.
 *
 * Plain HTTP (the page text is what is wanted, not a rendered browser), so it
 * never touches the Playwright browser the Google Maps scan depends on.
 *
 * Polite and bounded: one request at a time per site, a hard timeout and a
 * body-size cap on every request, at most `MAX_PAGES` pages, robots.txt
 * respected, and no attempt to get past a CAPTCHA, a bot check or an
 * authentication wall — such a site is reported as `check_failed`/`blocked`.
 *
 * Result statuses:
 *   found        at least one valid address was published
 *   not_found    every page that was read published none (and none failed)
 *   check_failed the site could not be read (timeout, error, blocked) and no
 *                address was found — it is NOT evidence that there is none
 *   not_checked  deliberately not visited (robots.txt, unusable URL)
 */

import net from 'node:net';
import {
  extractEmailsFromHtml,
  findContactPageLinks,
  looksLikeChallengePage,
  rankEmails,
  siteDomain,
  MAX_EMAILS_PER_SITE,
} from './emailExtraction.js';

export const USER_AGENT = 'Mozilla/5.0 (compatible; LeadFinderBot/1.0; business contact lookup)';
const DEFAULT_TIMEOUT_MS = 10_000;
const ROBOTS_TIMEOUT_MS = 5_000;
const MAX_BODY_BYTES = 1_500_000;
const MAX_REDIRECTS = 4;
const FETCH_ATTEMPTS = 2; // the first try and one retry, for timeouts/network/5xx only
const MAX_PAGES = 4; // the homepage plus up to three contact-type pages
const RETRY_BACKOFF_MS = 600;

const RETRYABLE_REASONS = new Set(['timeout', 'network_error', 'http_5xx']);
/** True when a `check_failed` is worth another attempt later. */
export const isRetryableReason = (reason) => RETRYABLE_REASONS.has(reason);

// ---- URL safety -----------------------------------------------------------

function isPrivateIp(host) {
  const kind = net.isIP(host);
  if (kind === 4) {
    const [a, b] = host.split('.').map(Number);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
  }
  if (kind === 6) return host === '::1' || /^(fc|fd|fe80)/i.test(host) || host === '::';
  return false;
}

/**
 * The website as an absolute http(s) URL, or null when it is not a public web
 * address. Google sometimes wraps the link as `google.com/url?q=<site>`.
 */
export function normalizeWebsiteUrl(raw) {
  if (!raw || typeof raw !== 'string') return null;
  let text = raw.trim();
  if (!text) return null;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(text)) text = `https://${text}`;
  let url;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  if (/(^|\.)google\.[a-z.]+$/i.test(url.hostname) && url.pathname === '/url') {
    const target = url.searchParams.get('q') || url.searchParams.get('url');
    return target ? normalizeWebsiteUrl(target) : null;
  }
  if (!/^https?:$/.test(url.protocol) || url.username || url.password) return null;
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (!host.includes('.') && !net.isIP(host)) return null; // "localhost", intranet names
  if (/\.(local|localhost|internal|lan|home|corp)$/.test(host) || isPrivateIp(host)) return null;
  url.hash = '';
  return url.href;
}

// ---- robots.txt -----------------------------------------------------------

/** Parses robots.txt into an `isAllowed(path)` for this crawler (our token, else `*`). */
export function parseRobots(text) {
  const groups = [];
  let current = null;
  let lastWasAgent = false;
  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.replace(/#.*/, '').trim();
    const m = line.match(/^([a-z-]+)\s*:\s*(.*)$/i);
    if (!m) continue;
    const field = m[1].toLowerCase();
    const value = m[2].trim();
    if (field === 'user-agent') {
      if (!current || !lastWasAgent) {
        current = { agents: [], rules: [] };
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
      lastWasAgent = true;
    } else if ((field === 'disallow' || field === 'allow') && current) {
      if (value) current.rules.push({ allow: field === 'allow', pattern: value });
      lastWasAgent = false;
    } else {
      lastWasAgent = false;
    }
  }
  const group = groups.find((g) => g.agents.some((a) => a !== '*' && 'leadfinderbot'.includes(a))) || groups.find((g) => g.agents.includes('*'));
  const rules = (group?.rules || []).map((r) => ({
    allow: r.allow,
    length: r.pattern.length,
    re: new RegExp(`^${r.pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\\\$$/, '$')}`),
  }));
  return {
    isAllowed(path) {
      let best = null;
      for (const r of rules) {
        if (r.re.test(path) && (!best || r.length > best.length || (r.length === best.length && r.allow))) best = r;
      }
      return best ? best.allow : true;
    },
  };
}

// ---- one request ----------------------------------------------------------

async function readCapped(res, cap) {
  if (!res.body?.getReader) return (await res.text()).slice(0, cap);
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let text = '';
  let bytes = 0;
  while (bytes < cap) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    text += decoder.decode(value, { stream: true });
  }
  await reader.cancel().catch(() => {});
  return text;
}

/**
 * One GET, following up to MAX_REDIRECTS redirects itself so that every hop is
 * checked to be a public address. Never throws.
 *
 * @returns {Promise<{ok: true, html: string, url: string} | {ok: false, reason: string, status?: number}>}
 */
async function fetchOnce(url, { fetchFn, timeoutMs }) {
  let current = url;
  try {
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      const res = await fetchFn(current, {
        method: 'GET',
        redirect: 'manual',
        signal: AbortSignal.timeout(timeoutMs),
        headers: { 'user-agent': USER_AGENT, accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5', 'accept-language': 'en-US,en;q=0.8' },
      });
      if (res.status >= 300 && res.status < 400 && res.headers.get('location')) {
        const next = normalizeWebsiteUrl(new URL(res.headers.get('location'), current).href);
        await res.body?.cancel?.().catch(() => {});
        if (!next) return { ok: false, reason: 'unsafe_redirect' };
        current = next;
        continue;
      }
      if (res.status === 401 || res.status === 403 || res.status === 429 || res.status === 451) {
        await res.body?.cancel?.().catch(() => {});
        return { ok: false, reason: 'blocked', status: res.status };
      }
      if (res.status === 404 || res.status === 410) {
        await res.body?.cancel?.().catch(() => {});
        return { ok: false, reason: 'not_found_page', status: res.status };
      }
      if (res.status >= 500) {
        const body = await readCapped(res, 60_000).catch(() => '');
        // A 503 from a bot-protection service is a block, not an outage.
        if (res.status === 503 && looksLikeChallengePage(body)) return { ok: false, reason: 'blocked', status: 503 };
        return { ok: false, reason: 'http_5xx', status: res.status };
      }
      if (res.status >= 400) {
        await res.body?.cancel?.().catch(() => {});
        return { ok: false, reason: 'http_error', status: res.status };
      }
      const type = res.headers.get('content-type') || '';
      if (type && !/text\/html|application\/xhtml|text\/plain/i.test(type)) {
        await res.body?.cancel?.().catch(() => {});
        return { ok: false, reason: 'not_html', status: res.status };
      }
      const html = await readCapped(res, MAX_BODY_BYTES);
      if (looksLikeChallengePage(html)) return { ok: false, reason: 'blocked', status: res.status };
      return { ok: true, html, url: current };
    }
    return { ok: false, reason: 'too_many_redirects' };
  } catch (err) {
    const timedOut = err?.name === 'TimeoutError' || err?.name === 'AbortError';
    return { ok: false, reason: timedOut ? 'timeout' : 'network_error' };
  }
}

async function fetchWithRetry(url, opts) {
  let result;
  for (let attempt = 1; attempt <= FETCH_ATTEMPTS; attempt++) {
    result = await fetchOnce(url, opts);
    if (result.ok || !isRetryableReason(result.reason)) return result;
    if (attempt < FETCH_ATTEMPTS) await opts.sleep(RETRY_BACKOFF_MS * attempt);
  }
  return result;
}

async function loadRobots(origin, opts) {
  const res = await fetchOnce(`${origin}/robots.txt`, { ...opts, timeoutMs: ROBOTS_TIMEOUT_MS });
  // No robots.txt, or one we cannot read, leaves the site open to ordinary visitors.
  return res.ok ? parseRobots(res.html) : parseRobots('');
}

// ---- the crawl ------------------------------------------------------------

/**
 * @param {string} websiteUrl
 * @param {object} [opts]
 * @param {typeof fetch} [opts.fetchFn] - test seam
 * @param {number} [opts.timeoutMs]
 * @param {number} [opts.maxPages]
 * @param {(ms: number) => Promise<void>} [opts.sleep] - test seam
 * @returns {Promise<{status: 'found'|'not_found'|'check_failed'|'not_checked', reason: string|null, emails: {address: string, sourceUrl: string}[], pagesChecked: number, website: string|null}>}
 */
export async function crawlSiteForEmails(websiteUrl, {
  fetchFn = globalThis.fetch,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  maxPages = MAX_PAGES,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
} = {}) {
  const opts = { fetchFn, timeoutMs, sleep };
  const result = (status, reason, emails = [], pagesChecked = 0, website = null) => ({ status, reason, emails, pagesChecked, website });

  const start = normalizeWebsiteUrl(websiteUrl);
  if (!start) return result('not_checked', 'invalid_url');
  const origin = new URL(start).origin;
  const hostname = new URL(start).hostname;

  const robots = await loadRobots(origin, opts);
  if (!robots.isAllowed(new URL(start).pathname || '/')) return result('not_checked', 'robots_disallowed', [], 0, start);

  const home = await fetchWithRetry(start, opts);
  if (!home.ok) {
    const reason = home.reason === 'not_found_page' ? 'http_404' : home.reason;
    return result('check_failed', reason, [], 0, start);
  }

  /** @type {Map<string, string>} address -> the page it was published on */
  const found = new Map();
  const collect = (html, url) => {
    for (const address of extractEmailsFromHtml(html)) if (!found.has(address)) found.set(address, url);
  };
  const site = siteDomain(hostname);
  const ownDomain = (list) => list.some((e) => siteDomain(e.slice(e.indexOf('@') + 1)) === site);

  collect(home.html, home.url);
  let pagesChecked = 1;
  let failure = null;

  // The homepage already names an address on the business's own domain: done.
  if (!ownDomain([...found.keys()])) {
    for (const link of findContactPageLinks(home.html, home.url, maxPages - 1)) {
      if (pagesChecked >= maxPages) break;
      if (!robots.isAllowed(new URL(link).pathname)) continue;
      const page = await fetchWithRetry(link, opts);
      pagesChecked += 1;
      if (page.ok) {
        collect(page.html, page.url);
        if (ownDomain([...found.keys()])) break;
      } else if (page.reason !== 'not_found_page') {
        failure = failure || page.reason;
      }
    }
  }

  const ranked = rankEmails([...found.keys()], hostname).slice(0, MAX_EMAILS_PER_SITE);
  const emails = ranked.map((address) => ({ address, sourceUrl: found.get(address) }));
  if (emails.length) return result('found', null, emails, pagesChecked, start);
  // A page that could not be read might have held the address: not "none".
  if (failure) return result('check_failed', failure, [], pagesChecked, start);
  return result('not_found', null, [], pagesChecked, start);
}

/**
 * One page, fetched with the same guards as the crawl: a public http(s) address,
 * robots.txt respected, a timeout and a body cap, never throwing. For pages that
 * are not a business's own site (a web search's results).
 *
 * @returns {Promise<{ok: true, html: string, url: string} | {ok: false, reason: string}>}
 */
export async function fetchPage(url, {
  fetchFn = globalThis.fetch,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
} = {}) {
  const start = normalizeWebsiteUrl(url);
  if (!start) return { ok: false, reason: 'invalid_url' };
  const opts = { fetchFn, timeoutMs, sleep };
  const { origin, pathname } = new URL(start);
  const robots = await loadRobots(origin, opts);
  if (!robots.isAllowed(pathname || '/')) return { ok: false, reason: 'robots_disallowed' };
  return fetchWithRetry(start, opts);
}
