/**
 * Public-HTML website analysis. Only reports issues with evidence from
 * the fetched page — never invents missing booking systems or "outdated
 * design" from a gut feel.
 */

import * as cheerio from 'cheerio';
import { originFromWebsite } from './emailDiscoveryService.js';

const FETCH_TIMEOUT_MS = 15000;
const MAX_HTML_BYTES = 1_500_000;

function observation(title, description, evidence) {
  return { title, description, evidence };
}

async function fetchPage(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  const started = Date.now();
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        'User-Agent': 'LeadFinderOutreach/1.0 (+website analysis)',
        Accept: 'text/html,application/xhtml+xml',
      },
    });
    const buf = Buffer.from(await res.arrayBuffer());
    const html = buf.subarray(0, MAX_HTML_BYTES).toString('utf8');
    return {
      ok: res.ok,
      status: res.status,
      html,
      bytes: buf.length,
      elapsedMs: Date.now() - started,
      finalUrl: res.url,
      headers: {
        contentType: res.headers.get('content-type') || '',
      },
    };
  } finally {
    clearTimeout(timer);
  }
}

export function analyzeHtml({ html, bytes, elapsedMs, finalUrl, status }) {
  const issues = [];
  const opportunities = [];
  const evidence = [];
  const $ = cheerio.load(html || '');

  const viewport = $('meta[name="viewport"]').attr('content') || '';
  const hasViewport = /width\s*=\s*device-width/i.test(viewport);
  evidence.push(hasViewport ? 'viewport meta present' : 'no device-width viewport meta');
  if (!hasViewport) {
    issues.push(observation(
      'No mobile viewport tag',
      'The homepage HTML does not declare a device-width viewport, which usually means the layout is not set up for phones.',
      'Missing meta name="viewport" content including width=device-width',
    ));
    opportunities.push(observation(
      'Mobile-friendly layout',
      'A responsive layout would make the site usable on phones.',
      'No device-width viewport meta',
    ));
  }

  const title = ($('title').first().text() || '').trim();
  const metaDesc = $('meta[name="description"]').attr('content') || '';
  evidence.push(title ? `title: ${title.slice(0, 80)}` : 'no <title>');
  if (!title) {
    issues.push(observation('Missing page title', 'The homepage has no <title> tag.', 'Empty or missing <title>'));
  }
  if (!metaDesc.trim()) {
    issues.push(observation(
      'Missing meta description',
      'No meta description was found on the homepage, which is a basic SEO signal search engines use.',
      'Missing meta name="description"',
    ));
  }

  const navCount = $('nav a, header a, [role="navigation"] a').length;
  evidence.push(`nav links: ${navCount}`);
  if (navCount < 2) {
    issues.push(observation(
      'Limited navigation',
      'The homepage has very few navigation links, so visitors may not have a clear way to browse services or contact pages.',
      `Counted ${navCount} nav/header links`,
    ));
  }

  const hasTel = $('a[href^="tel:"]').length > 0;
  const hasMailto = $('a[href^="mailto:"]').length > 0;
  const contactText = $('a, button').filter((_, el) => /contact|book|call us/i.test($(el).text())).length;
  evidence.push(`tel:${hasTel} mailto:${hasMailto} contact-like:${contactText}`);
  if (!hasTel && !hasMailto && contactText === 0) {
    issues.push(observation(
      'Contact details not obvious',
      'No tel:, mailto:, or contact-labelled link was found on the homepage.',
      'No telephone, email, or contact CTA in homepage HTML',
    ));
    opportunities.push(observation(
      'Clear contact path',
      'A visible phone, email, or contact form on the homepage would make it easier for customers to get in touch.',
      'No contact link detected',
    ));
  }

  const ctaHits = $('a, button').filter((_, el) =>
    /book|order|shop|get started|sign up|reserve|appointment|quote/i.test($(el).text()),
  ).length;
  evidence.push(`cta-like controls: ${ctaHits}`);
  if (ctaHits === 0) {
    issues.push(observation(
      'No obvious call to action',
      'Homepage links and buttons do not include common action wording such as book, order, or get started.',
      'Zero CTA-keyword matches in a/button text',
    ));
  }

  const bookingHits = /book online|reservations?|order online|add to cart|checkout|schedule/i.test($.text());
  evidence.push(`booking/order keywords: ${bookingHits}`);
  if (!bookingHits) {
    issues.push(observation(
      'No clear online booking or order flow',
      'The homepage text does not mention booking, reservations, or ordering online.',
      'No booking/order keywords in homepage text',
    ));
    opportunities.push(observation(
      'Online booking or enquiry form',
      'If customers currently have to call or message to book, a simple online flow can capture demand after hours.',
      'No booking/order keywords on homepage',
    ));
  }

  const social = [];
  $('a[href]').each((_, el) => {
    const href = ($(el).attr('href') || '').toLowerCase();
    if (/facebook\.com|instagram\.com|tiktok\.com|linkedin\.com|youtube\.com|twitter\.com|x\.com/.test(href)) {
      social.push(href.split('?')[0]);
    }
  });
  evidence.push(`social links: ${social.length}`);

  const forms = $('form').length;
  evidence.push(`forms: ${forms}`);

  const https = /^https:/i.test(finalUrl || '');
  if (!https) {
    issues.push(observation(
      'Not served over HTTPS',
      'The final URL was not HTTPS, which browsers flag as not secure.',
      `finalUrl=${finalUrl}`,
    ));
  }

  if (typeof bytes === 'number' && bytes > 2_000_000) {
    issues.push(observation(
      'Large homepage payload',
      'The HTML response is over 2 MB, which is a rough indicator the page may load slowly, especially on mobile.',
      `bytes=${bytes}`,
    ));
    opportunities.push(observation(
      'Faster page load',
      'Reducing homepage weight usually improves first impressions on phones.',
      `bytes=${bytes}`,
    ));
  }

  if (typeof elapsedMs === 'number' && elapsedMs > 4000) {
    issues.push(observation(
      'Slow first response',
      'The homepage took more than 4 seconds to respond in this check. That is only one sample, but it is a useful speed indicator.',
      `elapsedMs=${elapsedMs}`,
    ));
  }

  if (status && status >= 400) {
    issues.push(observation(
      'Homepage did not load cleanly',
      `The server responded with HTTP ${status}.`,
      `status=${status}`,
    ));
  }

  let score = 100;
  score -= issues.length * 8;
  if (hasViewport) score += 4;
  if (title && metaDesc.trim()) score += 4;
  if (ctaHits > 0) score += 4;
  if (bookingHits) score += 6;
  if (https) score += 4;
  score = Math.max(12, Math.min(96, score));

  return {
    score,
    issues,
    opportunities,
    signals: {
      hasViewport,
      title: title || null,
      hasMetaDescription: Boolean(metaDesc.trim()),
      navCount,
      hasTel,
      hasMailto,
      ctaHits,
      bookingHits,
      socialCount: social.length,
      forms,
      https,
      bytes: bytes ?? null,
      elapsedMs: elapsedMs ?? null,
      finalUrl: finalUrl || null,
    },
    evidence,
  };
}

export async function analyzeWebsite(website) {
  const origin = originFromWebsite(website);
  if (!origin) {
    return {
      score: 18,
      issues: [
        observation(
          'No public website found',
          'This listing does not include a website URL, so there is no public site to review.',
          website ? `Unusable website field: ${String(website).slice(0, 80)}` : 'website field empty',
        ),
      ],
      opportunities: [
        observation(
          'New business website',
          'A simple, mobile-friendly site with contact details and a clear call to action would give customers a place to find this business online.',
          'No website URL on the listing',
        ),
      ],
      signals: { hasWebsite: false },
      skipped: true,
      reason: 'no_website',
    };
  }

  try {
    const page = await fetchPage(`${origin}/`);
    const analysis = analyzeHtml(page);
    analysis.signals.hasWebsite = true;
    analysis.skipped = false;
    return analysis;
  } catch (err) {
    return {
      score: 22,
      issues: [
        observation(
          'Website could not be fetched',
          'The site did not respond in time or blocked this request, so no further observations were made.',
          err.message || String(err),
        ),
      ],
      opportunities: [],
      signals: { hasWebsite: true, fetchFailed: true },
      skipped: true,
      reason: 'fetch_failed',
      lastError: err.message || String(err),
    };
  }
}
