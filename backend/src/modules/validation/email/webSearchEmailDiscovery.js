/**
 * Email discovery for businesses that have NO website of their own — the
 * "website leads". Crawling a site (`emailDiscoveryService.js`) isn't an
 * option for them, so this looks the business up on the public web by name,
 * address and phone, then reads the pages that come back.
 *
 * Precision matters more than recall here: a wrong address is worse than no
 * address. Three guards keep other businesses' emails out:
 *   1. a result page only counts if it shows the business's phone number
 *      (or, with no phone on file, its full name AND its city);
 *   2. aggregator/social domains are never a source of the business's own
 *      address (yelp.com's support@ is not the pizzeria's email);
 *   3. a page that isn't the business's own site and lists more than a few
 *      distinct addresses is a directory page — skipped.
 *
 * When a result looks like the business's own site (its hostname carries the
 * business name), that site is also crawled with the normal discovery, since
 * its contact page is the best source there is.
 */

import * as cheerio from 'cheerio';
import {
  discoverEmailsFromWebsite,
  extractEmailsFromHtml,
  fetchHtml,
  originFromWebsite,
} from './emailDiscoveryService.js';

const SEARCH_URL = 'https://html.duckduckgo.com/html/';
const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
const MAX_RESULTS = 6;
const MAX_ADDRESSES_ON_NON_OWN_PAGE = 3;
// Minimum gap between two searches from this process — one IP firing
// searches back-to-back is exactly what trips a search engine's bot check.
const MIN_SEARCH_GAP_MS = 1800;
const SEARCH_JITTER_MS = 1200;

/** Hosts that are directories, social networks or platforms: never treated as
 * the business's own site, and no address at them is the business's. */
const AGGREGATOR_HOSTS = [
  'facebook.com', 'instagram.com', 'linkedin.com', 'twitter.com', 'x.com', 'tiktok.com',
  'youtube.com', 'pinterest.com', 'yelp.com', 'yellowpages.com', 'mapquest.com', 'bbb.org',
  'manta.com', 'tripadvisor.com', 'foursquare.com', 'google.com', 'bing.com', 'apple.com',
  'nextdoor.com', 'angi.com', 'angieslist.com', 'thumbtack.com', 'chamberofcommerce.com',
  'superpages.com', 'whitepages.com', 'dnb.com', 'zoominfo.com', 'opencorporates.com',
  'wikipedia.org', 'indeed.com', 'glassdoor.com', 'doordash.com', 'ubereats.com',
  'grubhub.com', 'opentable.com', 'groupon.com', 'wixsite.com',
];

// Social/login-walled pages are JS shells — fetching them yields no emails.
const SKIP_FETCH_HOSTS = ['facebook.com', 'instagram.com', 'linkedin.com', 'twitter.com', 'x.com', 'tiktok.com', 'youtube.com', 'pinterest.com'];

const NAME_STOPWORDS = new Set(['the', 'and', 'inc', 'llc', 'ltd', 'co', 'corp', 'company', 'of', 'at', 'in', 'on', 'for']);

export class SearchBlockedError extends Error {
  constructor(message = 'Web search is rate-limiting this connection') {
    super(message);
    this.code = 'SEARCH_BLOCKED';
  }
}

function hostOf(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '').toLowerCase();
  } catch {
    return '';
  }
}

function isHostIn(host, list) {
  return list.some((h) => host === h || host.endsWith(`.${h}`));
}

export function phoneDigits(phone) {
  const d = String(phone || '').replace(/\D/g, '');
  return d.length >= 10 ? d.slice(-10) : '';
}

function nameTokens(business) {
  return String(business || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((t) => t.length >= 3 && !NAME_STOPWORDS.has(t));
}

/** City guess from a "street, City, ST 12345" style address. */
export function cityFromAddress(address) {
  const parts = String(address || '').split(',').map((p) => p.trim()).filter(Boolean);
  if (parts.length >= 3) return parts[parts.length - 2];
  if (parts.length === 2) return parts[0];
  return '';
}

/**
 * Does this page's text plausibly describe THIS business?
 * Phone number present is decisive; otherwise the full name plus the city.
 */
export function pageMatchesBusiness(text, { business, phone, address }) {
  const body = String(text || '').toLowerCase();
  const wantedPhone = phoneDigits(phone);
  if (wantedPhone) {
    const digits = body.replace(/\D/g, '');
    return digits.includes(wantedPhone);
  }
  const tokens = nameTokens(business);
  if (!tokens.length) return false;
  const city = cityFromAddress(address).toLowerCase();
  if (!city) return false;
  return tokens.every((t) => body.includes(t)) && body.includes(city);
}

/** Hostname carries the business's name ("joespizzatx.com" for "Joe's Pizza"). */
export function looksLikeOwnSite(host, business) {
  if (!host || isHostIn(host, AGGREGATOR_HOSTS)) return false;
  const compact = host.replace(/[^a-z0-9]/g, '');
  const tokens = nameTokens(business);
  if (!tokens.length) return false;
  const hits = tokens.filter((t) => compact.includes(t)).length;
  return hits >= Math.min(2, tokens.length);
}

function decodeResultUrl(href) {
  try {
    const abs = href.startsWith('//') ? `https:${href}` : href;
    const u = new URL(abs);
    const target = u.searchParams.get('uddg');
    return target ? decodeURIComponent(target) : abs;
  } catch {
    return null;
  }
}

let lastSearchAt = 0;
let searchChain = Promise.resolve();

/** Serializes searches and spaces them out, whichever worker asks. */
function paced(fn, { minGapMs = MIN_SEARCH_GAP_MS, jitterMs = SEARCH_JITTER_MS } = {}) {
  const run = searchChain.then(async () => {
    const wait = lastSearchAt + minGapMs + Math.random() * jitterMs - Date.now();
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    try {
      return await fn();
    } finally {
      lastSearchAt = Date.now();
    }
  });
  searchChain = run.catch(() => {});
  return run;
}

export async function duckDuckGoSearch(query) {
  const url = `${SEARCH_URL}?q=${encodeURIComponent(query)}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  let res;
  try {
    res = await fetch(url, {
      signal: controller.signal,
      headers: { 'User-Agent': USER_AGENT, Accept: 'text/html' },
    });
  } finally {
    clearTimeout(timer);
  }
  const html = await res.text();
  // DuckDuckGo answers a flagged client with 202/403 or an "anomaly" page
  // instead of results — surface that as a stop signal, not "no results".
  if (res.status === 202 || res.status === 403 || res.status === 429 || /anomaly-modal|anomaly\.js|cc=botnet/i.test(html)) {
    throw new SearchBlockedError();
  }
  if (!res.ok) throw new Error(`Web search failed (HTTP ${res.status})`);

  const $ = cheerio.load(html);
  const urls = [];
  $('a.result__a').each((_, el) => {
    const target = decodeResultUrl($(el).attr('href') || '');
    if (target && /^https?:\/\//i.test(target) && !urls.includes(target)) urls.push(target);
  });
  return urls;
}

/**
 * @param {{ business: string, address?: string, location?: string, phone?: string }} lead
 * @param {object} [deps] test seams
 * @returns same shape as `discoverEmailsFromWebsite`, plus `foundOn` (the page
 *   the primary address came from) and `website` (the business's own site if
 *   one turned up).
 */
export async function discoverEmailsByWebSearch(lead, deps = {}) {
  const {
    searchFn = (q) => paced(() => duckDuckGoSearch(q)),
    fetchPageFn = fetchHtml,
    crawlFn = discoverEmailsFromWebsite,
  } = deps;

  const business = String(lead.business || '').trim();
  if (!business) {
    return { emails: [], primary: null, emailSource: null, pagesFetched: 0, lastError: 'No business name to search for' };
  }
  const place = lead.address || lead.location || '';
  const query = [business, place, lead.phone || ''].join(' ').replace(/\s+/g, ' ').trim().slice(0, 180);

  const urls = (await searchFn(query)).slice(0, MAX_RESULTS);
  if (!urls.length) {
    return { emails: [], primary: null, emailSource: null, pagesFetched: 0, lastError: 'Web search returned no results', searched: true };
  }

  const found = new Map(); // email -> { email, source, score, foundOn }
  let pagesFetched = 0;
  let website = null;
  let ownSiteOrigin = null;

  const remember = (email, source, score, foundOn) => {
    const prev = found.get(email);
    if (!prev || score > prev.score) found.set(email, { email, source, score, foundOn });
  };

  for (const url of urls) {
    const host = hostOf(url);
    if (!host || isHostIn(host, SKIP_FETCH_HOSTS)) continue;

    const page = await fetchPageFn(url);
    if (!page.ok) continue;
    pagesFetched += 1;

    const text = cheerio.load(page.html).text();
    if (!pageMatchesBusiness(text, { business, phone: lead.phone, address: place })) continue;

    const own = looksLikeOwnSite(host, business);
    if (own && !ownSiteOrigin) {
      ownSiteOrigin = originFromWebsite(url);
      website = ownSiteOrigin;
    }

    // Aggregators never supply the business's own address.
    if (isHostIn(host, AGGREGATOR_HOSTS)) continue;

    const onPage = [...new Set(extractEmailsFromHtml(page.html).map((e) => e.email))]
      .filter((email) => !isHostIn(email.split('@')[1], AGGREGATOR_HOSTS));
    if (!own && onPage.length > MAX_ADDRESSES_ON_NON_OWN_PAGE) continue;

    for (const email of onPage) {
      const sameDomain = own && email.split('@')[1].endsWith(host);
      remember(email, own ? 'website' : 'web_search', 20 + (own ? 20 : 0) + (sameDomain ? 15 : 0), url);
    }
  }

  // The business's own site, once identified, gets the full contact-page crawl.
  if (ownSiteOrigin) {
    try {
      const crawled = await crawlFn(ownSiteOrigin);
      pagesFetched += crawled.pagesFetched || 0;
      for (const e of crawled.emails || []) remember(e.email, e.source || 'website', (e.score || 10) + 25, ownSiteOrigin);
    } catch {
      // The pages already read above still count.
    }
  }

  const ranked = [...found.values()].sort((a, b) => b.score - a.score);
  const best = ranked[0] || null;
  return {
    emails: ranked,
    primary: best?.email || null,
    emailSource: best?.source || null,
    foundOn: best?.foundOn || null,
    website,
    pagesFetched,
    searched: true,
    lastError: ranked.length ? null : 'No email found on pages that mention this business',
  };
}

/** Test hook: lets tests run searches back-to-back. */
export function _resetPacingForTests() {
  lastSearchAt = 0;
  searchChain = Promise.resolve();
}
