/**
 * Polite, safe page fetching for employer career pages.
 *
 *  - robots.txt is read (and cached per origin) and obeyed for every hop;
 *  - only public http(s) addresses (the website module's URL check);
 *  - redirects are followed by hand so every hop is checked again;
 *  - bounded time and body size;
 *  - a CAPTCHA / bot-protection page is reported as `blocked` and left alone —
 *    nothing here tries to solve, evade or wait out a challenge.
 */

import { SourceError } from './errors.js';
import { DEFAULT_USER_AGENT } from './http.js';
import { normalizeWebsiteUrl, parseRobots } from '../../website/websiteFetcher.js';
import { looksLikeChallengePage } from '../../website/emailExtraction.js';

const ROBOTS_TTL_MS = 60 * 60_000;
const ROBOTS_TIMEOUT_MS = 6_000;

export function createRobotsChecker({ fetchImpl = globalThis.fetch, userAgent = DEFAULT_USER_AGENT, now = Date.now } = {}) {
  const cache = new Map(); // origin -> { at, rules }

  async function rulesFor(origin) {
    const hit = cache.get(origin);
    if (hit && now() - hit.at < ROBOTS_TTL_MS) return hit.rules;
    let rules;
    try {
      const res = await fetchImpl(`${origin}/robots.txt`, { headers: { 'user-agent': userAgent }, signal: AbortSignal.timeout(ROBOTS_TIMEOUT_MS), redirect: 'follow' });
      // No robots.txt (or an unreadable one) leaves the site open to ordinary visitors.
      rules = res.ok ? parseRobots(await res.text()) : parseRobots('');
    } catch {
      rules = parseRobots('');
    }
    cache.set(origin, { at: now(), rules });
    return rules;
  }

  return {
    async isAllowed(url) {
      const u = new URL(url);
      const rules = await rulesFor(u.origin);
      return rules.isAllowed(`${u.pathname}${u.search}`);
    },
  };
}

/**
 * @returns {Promise<{html: string, url: string}>}
 * @throws {SourceError}
 */
export async function fetchHtmlSafe(rawUrl, { fetchImpl = globalThis.fetch, robots, timeoutMs = 15_000, maxBytes = 2_000_000, userAgent = DEFAULT_USER_AGENT, maxRedirects = 4, normalizeUrl = normalizeWebsiteUrl } = {}) {
  let current = normalizeUrl(rawUrl);
  if (!current) throw new SourceError('disallowed', 'Not a public http(s) address', { retryable: false });

  for (let hop = 0; hop <= maxRedirects; hop++) {
    if (robots && !(await robots.isAllowed(current))) {
      throw new SourceError('disallowed', 'robots.txt does not allow collecting this page', { retryable: false });
    }
    let res;
    try {
      res = await fetchImpl(current, {
        method: 'GET',
        redirect: 'manual',
        signal: AbortSignal.timeout(timeoutMs),
        headers: { 'user-agent': userAgent, accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5', 'accept-language': 'en-US,en;q=0.8' },
      });
    } catch (err) {
      const timedOut = err?.name === 'TimeoutError' || err?.name === 'AbortError';
      throw new SourceError(timedOut ? 'timeout' : 'network', timedOut ? 'Request timed out' : 'Network error', { retryable: true, cause: err });
    }

    if (res.status >= 300 && res.status < 400 && res.headers.get('location')) {
      await res.body?.cancel?.().catch(() => {});
      const next = normalizeUrl(new URL(res.headers.get('location'), current).href);
      if (!next) throw new SourceError('disallowed', 'Redirected to a non-public address', { retryable: false });
      current = next;
      continue;
    }
    if (res.status === 404 || res.status === 410) {
      await res.body?.cancel?.().catch(() => {});
      throw new SourceError('not_found', `HTTP ${res.status}`, { status: res.status, retryable: false });
    }
    if (res.status === 401 || res.status === 403 || res.status === 451) {
      await res.body?.cancel?.().catch(() => {});
      throw new SourceError('blocked', `HTTP ${res.status} (access denied — not bypassed)`, { status: res.status, retryable: false });
    }
    if (res.status === 429) {
      await res.body?.cancel?.().catch(() => {});
      throw new SourceError('rate_limited', 'HTTP 429', { status: 429, retryable: true });
    }
    if (res.status >= 400) {
      await res.body?.cancel?.().catch(() => {});
      throw new SourceError('http_error', `HTTP ${res.status}`, { status: res.status, retryable: res.status >= 500 });
    }
    const type = res.headers.get('content-type') || '';
    if (type && !/text\/html|application\/xhtml|text\/plain/i.test(type)) {
      await res.body?.cancel?.().catch(() => {});
      throw new SourceError('parse', 'Not an HTML page', { retryable: false });
    }
    const html = (await res.text()).slice(0, maxBytes);
    if (looksLikeChallengePage(html)) throw new SourceError('blocked', 'The site served a bot-protection page (not bypassed)', { retryable: false });
    return { html, url: current };
  }
  throw new SourceError('http_error', 'Too many redirects', { retryable: false });
}
