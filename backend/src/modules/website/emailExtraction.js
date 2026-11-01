/**
 * Pulls publicly published business email addresses out of a web page.
 *
 * Pure: HTML in, addresses out. Nothing here fetches, guesses or builds an
 * address — an address is returned only if the page itself publishes it, in a
 * `mailto:` link, in the visible text, or in Cloudflare's `data-cfemail`
 * encoding (which the browser decodes for every visitor).
 */

import * as cheerio from 'cheerio';

/** Per business: more than this is almost always a directory, not a contact. */
export const MAX_EMAILS_PER_SITE = 5;

const EMAIL_IN_TEXT = /[a-z0-9][a-z0-9._%+'-]{0,63}@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+/gi;

// "logo@2x.png", "sprite@3x.webp": file names, not mailboxes.
const FILE_EXTENSIONS = new Set([
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'bmp', 'avif', 'js', 'css', 'json', 'woff', 'woff2', 'ttf', 'map', 'mp4', 'pdf',
]);

// Example/placeholder and platform addresses that appear in page templates and
// error trackers, never as a business's contact.
const BLOCKED_DOMAINS = new Set([
  'example.com', 'example.org', 'example.net', 'domain.com', 'yourdomain.com', 'email.com', 'test.com', 'mysite.com',
  'sentry.io', 'sentry.wixpress.com', 'wixpress.com', 'sentry-next.wixpress.com',
]);
const BLOCKED_LOCALS = new Set(['your', 'you', 'name', 'yourname', 'user', 'username', 'email', 'youremail', 'someone', 'test', 'example']);
const NO_REPLY = /^(no[-_.]?reply|do[-_.]?not[-_.]?reply|mailer[-_.]?daemon|postmaster|bounce)/i;

/** Lower-cases and trims; strips a `mailto:` prefix, query string and stray punctuation. */
export function normalizeEmail(raw) {
  if (raw == null) return null;
  let value = String(raw).trim();
  try {
    value = decodeURIComponent(value);
  } catch {
    // keep as is
  }
  value = value.replace(/^mailto:/i, '').split('?')[0].trim();
  value = value.replace(/^[<("'\s]+|[>)"'\s.,;:!]+$/g, '');
  return value ? value.toLowerCase() : null;
}

/** True for a syntactically valid, plausible mailbox. Rejects placeholders and file names. */
export function isValidBusinessEmail(email) {
  if (typeof email !== 'string' || email.length > 254) return false;
  const at = email.lastIndexOf('@');
  if (at < 1 || at !== email.indexOf('@')) return false;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  if (local.length > 64 || local.startsWith('.') || local.endsWith('.') || local.includes('..')) return false;
  if (!/^[a-z0-9._%+'-]+$/.test(local)) return false;
  const labels = domain.split('.');
  if (labels.length < 2 || labels.some((l) => !l || l.length > 63 || !/^[a-z0-9-]+$/.test(l) || l.startsWith('-') || l.endsWith('-'))) {
    return false;
  }
  const tld = labels[labels.length - 1];
  if (!/^[a-z]{2,24}$/.test(tld) || FILE_EXTENSIONS.has(tld)) return false;
  if (BLOCKED_DOMAINS.has(domain) || BLOCKED_LOCALS.has(local) || NO_REPLY.test(local)) return false;
  return true;
}

/** Decodes Cloudflare's `data-cfemail` (hex: first byte is the XOR key). */
function decodeCloudflareEmail(hex) {
  if (!/^[0-9a-f]{4,}$/i.test(hex) || hex.length % 2) return null;
  const key = parseInt(hex.slice(0, 2), 16);
  let out = '';
  for (let i = 2; i < hex.length; i += 2) out += String.fromCharCode(parseInt(hex.slice(i, i + 2), 16) ^ key);
  return out;
}

/**
 * The valid, de-duplicated addresses a page publishes, in page order.
 *
 * @param {string} html
 * @returns {string[]}
 */
export function extractEmailsFromHtml(html) {
  if (!html || typeof html !== 'string') return [];
  const $ = cheerio.load(html);
  const found = [];

  $('a[href^="mailto:" i]').each((_, el) => {
    // A mailto may list several recipients: mailto:a@x.com,b@x.com?subject=Hi
    const href = ($(el).attr('href') || '').replace(/^mailto:/i, '').split('?')[0];
    for (const part of href.split(/[,;]/)) found.push(part);
  });

  $('[data-cfemail]').each((_, el) => {
    const decoded = decodeCloudflareEmail($(el).attr('data-cfemail') || '');
    if (decoded) found.push(decoded);
  });

  // Visible text only: scripts and styles are full of "name@2x.png" noise.
  $('script, style, noscript').remove();
  // Neighbouring elements must not run together ("a@b.com</p><p>Next" is not "a@b.comNext").
  $('*').after(' ');
  const text = $.root().text();
  for (const m of text.matchAll(EMAIL_IN_TEXT)) found.push(m[0]);

  const seen = new Set();
  const out = [];
  for (const raw of found) {
    const email = normalizeEmail(raw);
    if (!email || seen.has(email) || !isValidBusinessEmail(email)) continue;
    seen.add(email);
    out.push(email);
  }
  return out;
}

/** The part of a host that identifies the business: `www.a.example.co.uk` -> `example.co.uk`-ish. */
export function siteDomain(hostname) {
  const labels = String(hostname || '').toLowerCase().replace(/^www\./, '').split('.');
  if (labels.length <= 2) return labels.join('.');
  const secondLevel = new Set(['co', 'com', 'org', 'net', 'gov', 'edu', 'ac']);
  return labels.slice(secondLevel.has(labels[labels.length - 2]) ? -3 : -2).join('.');
}

/** Puts addresses on the business's own domain first; they are the most likely to be its contact. */
export function rankEmails(emails, hostname) {
  const own = siteDomain(hostname);
  const onSite = (e) => siteDomain(e.slice(e.indexOf('@') + 1)) === own;
  return [...emails.filter(onSite), ...emails.filter((e) => !onSite(e))];
}

const CONTACT_HINT = /contact|about|reach|get-in-touch|getintouch|connect|support|team|impressum|find-us|locations?|visit/i;

/**
 * Same-site pages that are likely to publish a contact address, best first.
 * Only links on the site's own host are followed.
 *
 * @param {string} html
 * @param {string} baseUrl - the page the HTML came from
 * @param {number} [limit]
 * @returns {string[]} absolute URLs
 */
export function findContactPageLinks(html, baseUrl, limit = 3) {
  if (!html) return [];
  let base;
  try {
    base = new URL(baseUrl);
  } catch {
    return [];
  }
  const $ = cheerio.load(html);
  const scored = new Map();
  $('a[href]').each((_, el) => {
    const href = ($(el).attr('href') || '').trim();
    if (!href || /^(mailto:|tel:|javascript:|#)/i.test(href)) return;
    let url;
    try {
      url = new URL(href, base);
    } catch {
      return;
    }
    if (!/^https?:$/.test(url.protocol) || url.hostname.replace(/^www\./, '') !== base.hostname.replace(/^www\./, '')) return;
    url.hash = '';
    const path = url.pathname.toLowerCase();
    if (/\.(pdf|jpe?g|png|gif|webp|svg|zip|docx?|xlsx?)$/.test(path)) return;
    if (url.href === new URL(base.href).href) return;
    const label = $(el).text().trim();
    // The URL says more than the link text, and "contact" beats "about".
    let score = 0;
    if (/contact/i.test(path)) score += 4;
    else if (CONTACT_HINT.test(path)) score += 2;
    if (/contact/i.test(label)) score += 3;
    else if (CONTACT_HINT.test(label)) score += 1;
    if (score > 0 && (scored.get(url.href) ?? 0) < score) scored.set(url.href, score);
  });
  return [...scored.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit).map(([href]) => href);
}

const CHALLENGE_MARKERS = /g-recaptcha|h-captcha|hcaptcha|cf-challenge|challenge-platform|cf_chl|captcha-delivery|px-captcha|just a moment\.\.\.|attention required|verify you are (a )?human|access denied/i;

/** True when a response is a CAPTCHA / bot-check page rather than the site's content. */
export function looksLikeChallengePage(html) {
  if (!html) return false;
  const head = html.slice(0, 60000);
  if (!CHALLENGE_MARKERS.test(head)) return false;
  // A real page that merely embeds a reCAPTCHA contact form is long; a
  // challenge page is nearly empty.
  const $ = cheerio.load(html);
  $('script, style, noscript').remove();
  return $.root().text().replace(/\s+/g, ' ').trim().length < 1500;
}
