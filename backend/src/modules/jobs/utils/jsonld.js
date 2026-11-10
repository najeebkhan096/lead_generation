/**
 * schema.org `JobPosting` extraction from a page's JSON-LD — the structured
 * data employers publish precisely so that job search engines can read it.
 * Also discovers job-detail links on listing pages.
 */

import * as cheerio from 'cheerio';

function asArray(v) {
  return v == null ? [] : Array.isArray(v) ? v : [v];
}

function isJobPosting(node) {
  return asArray(node?.['@type']).some((t) => String(t).toLowerCase() === 'jobposting');
}

/** Walks @graph / ItemList / arrays and collects JobPosting nodes. */
function collect(node, out, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 6) return;
  if (Array.isArray(node)) {
    node.forEach((n) => collect(n, out, depth + 1));
    return;
  }
  if (isJobPosting(node)) out.push(node);
  if (node['@graph']) collect(node['@graph'], out, depth + 1);
  if (node.itemListElement) collect(asArray(node.itemListElement).map((e) => e?.item || e), out, depth + 1);
  if (node.mainEntity) collect(node.mainEntity, out, depth + 1);
}

/** @returns {object[]} JobPosting nodes found in [html] (malformed blocks are ignored). */
export function extractJobPostings(html) {
  const $ = cheerio.load(String(html || ''));
  const found = [];
  $('script[type="application/ld+json"]').each((_, el) => {
    const text = $(el).contents().text().trim();
    if (!text) return;
    try {
      collect(JSON.parse(text), found);
    } catch {
      // Some sites emit JSON-LD with stray control characters; one retry after cleaning them.
      try {
        collect(JSON.parse(text.replace(/[\u0000-\u001f]+/g, ' ')), found);
      } catch {
        /* unreadable block: skip it */
      }
    }
  });
  return found;
}

const DEFAULT_LINK = /job|career|position|opening|vacanc|opportunit|apply|stellen/i;
const SKIP_EXT = /\.(pdf|docx?|xlsx?|png|jpe?g|gif|svg|zip|mp4)(\?|$)/i;

/** Same-site links that look like individual job pages. */
export function discoverJobLinks(html, baseUrl, { pattern, limit = 30 } = {}) {
  const $ = cheerio.load(String(html || ''));
  const base = new URL(baseUrl);
  const re = pattern ? new RegExp(pattern, 'i') : null;
  const seen = new Set([base.href.replace(/#.*/, '')]);
  const out = [];
  $('a[href]').each((_, a) => {
    if (out.length >= limit) return false;
    let u;
    try {
      u = new URL($(a).attr('href'), base);
    } catch {
      return;
    }
    if (!/^https?:$/.test(u.protocol) || u.hostname.replace(/^www\./, '') !== base.hostname.replace(/^www\./, '')) return;
    u.hash = '';
    if (SKIP_EXT.test(u.pathname) || seen.has(u.href)) return;
    const target = `${u.pathname}${u.search}`;
    // Without an explicit pattern, require the link to be deeper than the listing page and job-like.
    const ok = re ? re.test(target) : DEFAULT_LINK.test(target) && u.pathname.split('/').filter(Boolean).length >= 2;
    if (!ok) return;
    seen.add(u.href);
    out.push(u.href);
  });
  return out;
}
