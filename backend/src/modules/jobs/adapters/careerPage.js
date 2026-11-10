/**
 * Employer career pages — public pages that publish their openings as
 * schema.org `JobPosting` structured data.
 *
 * Configure pages under this source's `careerPages` setting:
 *
 *   { company: 'Acme', url: 'https://acme.com/careers', website: 'https://acme.com',
 *     linkPattern: '/jobs/\\d+'   // optional: which links on a listing page are job pages
 *     maxDetailPages: 30,         // optional cap per page
 *     render: 'auto' | 'always' | 'never' }
 *
 * For each page: read the HTML (robots.txt obeyed, public addresses only) and
 * take its JobPosting JSON-LD. If the page is a listing without structured
 * data, follow its job links (same site, capped). If the static HTML has
 * nothing and the page is rendered by JavaScript, load it once in the shared
 * headless browser (Playwright) and look again.
 *
 * Never attempted: logging in, solving or waiting out CAPTCHAs, evading bot
 * protection. A page that blocks is reported as `blocked` and skipped.
 */

import crypto from 'node:crypto';
import { BoardAdapter } from './boardAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';
import { extractJobPostings, discoverJobLinks } from '../utils/jsonld.js';
import { createRobotsChecker, fetchHtmlSafe } from '../utils/safeFetch.js';
import { browserPool as sharedBrowserPool } from '../services/browserPool.js';
import { geoCatalog } from '../geo/geoCatalog.js';
import { htmlToText, textOrNull } from '../utils/text.js';
import { normalizeWebsiteUrl } from '../../website/websiteFetcher.js';

const DEFAULT_DETAIL_PAGES = 30;
const EMPLOYMENT = { FULL_TIME: 'full_time', PART_TIME: 'part_time', CONTRACTOR: 'contract', TEMPORARY: 'temporary', INTERN: 'internship', PER_DIEM: 'part_time' };
const UNIT = { HOUR: 'hour', DAY: 'day', WEEK: 'week', MONTH: 'month', YEAR: 'year' };

const asArray = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
const str = (v) => (typeof v === 'string' ? v : typeof v === 'number' ? String(v) : v?.name || v?.['@value'] || null);

export class CareerPageAdapter extends BoardAdapter {
  static meta = {
    id: 'career_page',
    name: 'Employer career pages',
    type: 'career',
    homepage: null,
    termsUrl: null,
    requiresKey: false,
    countries: '*',
    remoteOnly: false,
    defaultLimits: { perMinute: 12, perDay: 2000, maxConcurrent: 1 },
    defaultMaxPages: 1,
    description: "Employers' own career pages that publish schema.org JobPosting data. Add page URLs under \"careerPages\". Pages that disallow robots or show a bot wall are skipped.",
  };

  constructor(deps = {}) {
    super(deps);
    this.fetchHtml = deps.fetchHtml || null;
    this.browser = deps.browserPool || sharedBrowserPool;
    this.normalizeUrl = deps.normalizeUrl || normalizeWebsiteUrl;
    this.robots = deps.robots || createRobotsChecker({ fetchImpl: deps.fetchImpl });
    this.fetchImpl = deps.fetchImpl || globalThis.fetch;
  }

  boards() {
    const pages = Array.isArray(this.settings.careerPages) ? this.settings.careerPages : [];
    const out = [];
    const seen = new Set();
    for (const entry of pages) {
      const url = this.normalizeUrl(entry?.url);
      if (!url || seen.has(url)) continue;
      seen.add(url);
      out.push({
        id: crypto.createHash('sha1').update(url).digest('hex').slice(0, 12),
        url,
        name: textOrNull(entry.company),
        website: textOrNull(entry.website),
        linkPattern: entry.linkPattern || null,
        maxDetailPages: Math.min(100, Math.max(0, Number(entry.maxDetailPages ?? DEFAULT_DETAIL_PAGES))),
        render: ['auto', 'always', 'never'].includes(entry.render) ? entry.render : 'auto',
      });
    }
    return out;
  }

  configurationHint() {
    return 'Add at least one career page ({ company, url }) under this source\'s "careerPages" setting.';
  }

  /** One page, through the source's rate gate. */
  readPage(url) {
    return this.gate.run(() =>
      this.fetchHtml
        ? this.fetchHtml(url)
        : fetchHtmlSafe(url, { fetchImpl: this.fetchImpl, robots: this.robots, normalizeUrl: this.normalizeUrl }),
    );
  }

  async renderPage(url) {
    if (!(await this.robots.isAllowed(url))) throw new SourceError('disallowed', 'robots.txt does not allow collecting this page', { retryable: false });
    return this.gate.run(() => this.browser.render(url));
  }

  /** JobPostings of one page: static HTML first, then listing links, then the browser. */
  async postingsFor(board) {
    const found = [];
    const take = (html, url) => {
      for (const posting of extractJobPostings(html)) found.push({ posting, pageUrl: url });
      return found.length;
    };

    let page = null;
    if (board.render !== 'always') {
      page = await this.readPage(board.url); // blocked / disallowed / 404 propagate
      take(page.html, page.url);
    }
    if (!found.length && board.render !== 'never' && this.browser?.enabled !== false) {
      try {
        page = await this.renderPage(board.url);
        take(page.html, page.url);
      } catch (err) {
        // A missing browser must not fail a page the static fetch already read.
        if (!page) throw err;
        this.log.warn('browser fallback unavailable', { source: this.id, error: err });
      }
    }

    if (!found.length && page) {
      // A listing page: follow its job links.
      const links = discoverJobLinks(page.html, page.url, { pattern: board.linkPattern, limit: board.maxDetailPages });
      for (const link of links) {
        try {
          const detail = await this.readPage(link);
          take(detail.html, detail.url);
        } catch (err) {
          // One bad detail page is not the board's failure — but a bot wall ends the visit.
          if (err instanceof SourceError && (err.kind === 'blocked' || err.kind === 'quota')) break;
          this.log.warn('detail page skipped', { source: this.id, error: err });
        }
      }
    }
    return found;
  }

  async loadBoard(board) {
    const items = await this.postingsFor(board);
    return { company: { name: board.name, website: board.website }, items };
  }

  toJob({ posting, pageUrl }, board, company) {
    const orgName = str(posting.hiringOrganization);
    const locations = asArray(posting.jobLocation);
    const address = locations.map((l) => l?.address).find(Boolean) || {};
    const countryText = str(address.addressCountry);
    const countryCode = countryText ? geoCatalog.findCountryCode(countryText) : null;
    const salary = posting.baseSalary || {};
    const value = salary.value && typeof salary.value === 'object' ? salary.value : { value: salary.value };
    const identifier = posting.identifier && typeof posting.identifier === 'object' ? posting.identifier.value : posting.identifier;
    const url = posting.url || pageUrl;

    const extra = [
      posting.responsibilities && `Responsibilities:\n${htmlToText(str(posting.responsibilities))}`,
      posting.qualifications && `Qualifications:\n${htmlToText(str(posting.qualifications))}`,
    ].filter(Boolean);
    const months = posting.experienceRequirements?.monthsOfExperience;
    const skills = asArray(posting.skills).flatMap((s) => String(str(s) || '').split(/[,;]/)).map((s) => s.trim()).filter(Boolean);

    return buildJob({
      source: this.id,
      sourceJobId: textOrNull(identifier) || crypto.createHash('sha1').update(String(url)).digest('hex').slice(0, 16),
      sourceUrl: url,
      applyUrl: url,
      sourceRef: { board: board.id, pageUrl: url },
      title: str(posting.title),
      companyName: orgName || company.name,
      companyWebsite: str(posting.hiringOrganization?.sameAs) || str(posting.hiringOrganization?.url) || company.website,
      locationText: [address.addressLocality, address.addressRegion, countryText].map(str).filter(Boolean).join(', ') || undefined,
      countryCode,
      country: countryCode ? null : countryText,
      state: str(address.addressRegion),
      city: str(address.addressLocality),
      description: [htmlToText(posting.description), ...extra].filter(Boolean).join('\n\n'),
      employmentTypeText: asArray(posting.employmentType).join(' '),
      employmentType: EMPLOYMENT[String(asArray(posting.employmentType)[0] || '').toUpperCase()] || null,
      workArrangement: String(posting.jobLocationType || '').toUpperCase() === 'TELECOMMUTE' ? 'remote' : null,
      postedAt: posting.datePosted,
      deadlineAt: posting.validThrough,
      salaryMin: value.minValue ?? value.value,
      salaryMax: value.maxValue ?? value.value,
      salaryCurrency: salary.currency,
      salaryPeriod: UNIT[String(value.unitText || '').toUpperCase()] || null,
      experienceYearsMin: typeof months === 'number' ? Math.round(months / 12) : null,
      experienceText: typeof posting.experienceRequirements === 'string' ? posting.experienceRequirements : null,
      educationText: typeof posting.educationRequirements === 'string' ? posting.educationRequirements : str(posting.educationRequirements?.credentialCategory),
      tags: skills,
      raw: { identifier, url, datePosted: posting.datePosted, validThrough: posting.validThrough, directApply: posting.directApply },
    });
  }

  /** Re-reads the posting page: a 404/410 is a definitive "gone"; a blocked/failed read is unknown. */
  async getJobDetails(ref) {
    const pageUrl = ref.sourceRef?.pageUrl || ref.sourceUrl;
    if (!pageUrl) return { found: null, job: null };
    try {
      const { html, url } = await this.readPage(pageUrl);
      const hit = extractJobPostings(html)[0];
      if (!hit) return { found: null, job: null }; // the page loaded but we can't tell: don't guess
      const board = this.boards().find((b) => b.id === ref.sourceRef?.board) || { id: ref.sourceRef?.board || 'page', name: null, website: null };
      return { found: true, job: this.toJob({ posting: hit, pageUrl: url }, board, { name: board.name, website: board.website }) };
    } catch (err) {
      if (err instanceof SourceError && err.kind === 'not_found') return { found: false, job: null };
      throw err;
    }
  }
}
