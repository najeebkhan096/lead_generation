/**
 * Lever public postings — https://github.com/lever/postings-api
 *
 *   GET https://api.lever.co/v0/postings/{company}?mode=json
 *   (EU-hosted accounts: https://api.eu.lever.co/v0/postings/{company})
 */

import { BoardAdapter } from './boardAdapter.js';
import { buildJob } from './buildJob.js';
import { htmlToText } from '../utils/text.js';
import { SourceError } from '../utils/errors.js';

const hostFor = (board) => (String(board.region || '').toLowerCase() === 'eu' ? 'https://api.eu.lever.co' : 'https://api.lever.co');

/** Lever's `workplaceType` -> our vocabulary (unspecified stays unknown). */
function arrangement(value) {
  switch (String(value || '').toLowerCase()) {
    case 'remote':
      return 'remote';
    case 'hybrid':
      return 'hybrid';
    case 'on-site':
    case 'onsite':
      return 'onsite';
    default:
      return null;
  }
}

function salaryPeriod(interval) {
  const s = String(interval || '').toLowerCase();
  for (const p of ['year', 'month', 'week', 'day', 'hour']) if (s.includes(p)) return p;
  return null;
}

const prettify = (slug) => slug.replace(/[-_.]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

export class LeverAdapter extends BoardAdapter {
  static meta = {
    id: 'lever',
    name: 'Lever',
    type: 'ats',
    homepage: 'https://www.lever.co',
    termsUrl: 'https://github.com/lever/postings-api',
    requiresKey: false,
    countries: '*',
    remoteOnly: false,
    defaultLimits: { perMinute: 30, perDay: 1000, maxConcurrent: 1 },
    defaultMaxPages: 1,
    description: 'Public postings of companies that use Lever. Add the company slug (jobs.lever.co/<slug>); set region "eu" for EU-hosted accounts.',
  };

  async loadBoard(board) {
    const data = await this.getJson(`${hostFor(board)}/v0/postings/${encodeURIComponent(board.id)}`, { query: { mode: 'json' } });
    if (!Array.isArray(data)) throw new SourceError('parse', 'Unexpected Lever response', { retryable: false, source: this.id });
    return { company: { name: board.name || prettify(board.id), website: board.website }, items: data };
  }

  toJob(raw, board, company) {
    const lists = (raw.lists || []).map((l) => `${htmlToText(l.text)}:\n${htmlToText(l.content)}`).join('\n\n');
    const description = [raw.descriptionPlain || htmlToText(raw.description), lists, raw.additionalPlain || htmlToText(raw.additional)].filter(Boolean).join('\n\n');
    const range = raw.salaryRange;
    return buildJob({
      source: this.id,
      sourceJobId: raw.id,
      sourceUrl: raw.hostedUrl,
      applyUrl: raw.applyUrl || raw.hostedUrl,
      sourceRef: { board: board.id, region: board.region || null },
      title: raw.text,
      companyName: company.name,
      companyWebsite: company.website,
      locationText: raw.categories?.location || (raw.categories?.allLocations || [])[0],
      countryCode: raw.country,
      description,
      employmentTypeText: raw.categories?.commitment,
      workArrangement: arrangement(raw.workplaceType),
      postedAt: raw.createdAt,
      salaryMin: range?.min,
      salaryMax: range?.max,
      salaryCurrency: range?.currency,
      salaryPeriod: salaryPeriod(range?.interval),
      raw: { id: raw.id, categories: raw.categories, workplaceType: raw.workplaceType, salaryDescriptionPlain: raw.salaryDescriptionPlain },
    });
  }

  async getJobDetails(ref) {
    const board = { id: ref.sourceRef?.board, region: ref.sourceRef?.region };
    if (!board.id) return { found: null, job: null };
    try {
      const raw = await this.getJson(`${hostFor(board)}/v0/postings/${encodeURIComponent(board.id)}/${encodeURIComponent(ref.sourceJobId)}`);
      return { found: true, job: this.toJob(raw, board, { name: prettify(board.id), website: null }) };
    } catch (err) {
      if (err instanceof SourceError && err.kind === 'not_found') return { found: false, job: null };
      throw err;
    }
  }
}
