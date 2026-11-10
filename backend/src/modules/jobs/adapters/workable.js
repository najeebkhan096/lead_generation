/**
 * Workable public job feed (the account "widget" endpoint that powers
 * Workable's embeddable job widget; no key).
 *
 *   GET https://apply.workable.com/api/v1/widget/accounts/{account}?details=true
 *
 * NOTE: the endpoint was confirmed live (an empty account answers
 * `{name, description, jobs: []}`), but the field mapping below follows
 * Workable's documented widget payload and has not been exercised against a
 * board with open jobs.
 */

import { BoardAdapter } from './boardAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';
import { geoCatalog } from '../geo/geoCatalog.js';

export class WorkableAdapter extends BoardAdapter {
  static meta = {
    id: 'workable',
    name: 'Workable',
    type: 'ats',
    homepage: 'https://www.workable.com',
    termsUrl: 'https://workable.readme.io/',
    requiresKey: false,
    countries: '*',
    remoteOnly: false,
    defaultLimits: { perMinute: 20, perDay: 1000, maxConcurrent: 1 },
    defaultMaxPages: 1,
    description: 'Public job feeds of companies that use Workable. Add the account name (apply.workable.com/<account>).',
  };

  async loadBoard(board) {
    const data = await this.getJson(`https://apply.workable.com/api/v1/widget/accounts/${encodeURIComponent(board.id)}`, { query: { details: 'true' } });
    if (!data || !Array.isArray(data.jobs)) throw new SourceError('parse', 'Unexpected Workable response', { retryable: false, source: this.id });
    return { company: { name: board.name || data.name || board.id, website: board.website }, items: data.jobs };
  }

  toJob(raw, board, company) {
    const visible = (raw.locations || []).find((l) => !l.hidden) || null;
    const countryCode = raw.country ? geoCatalog.findCountryCode(raw.country) : visible?.countryCode || null;
    return buildJob({
      source: this.id,
      sourceJobId: raw.shortcode || raw.code,
      sourceUrl: raw.url || raw.shortlink,
      applyUrl: raw.application_url || raw.url,
      sourceRef: { board: board.id },
      title: raw.title,
      companyName: company.name,
      companyWebsite: company.website,
      locationText: [raw.city, raw.state, raw.country].filter(Boolean).join(', ') || undefined,
      countryCode,
      country: countryCode ? null : raw.country,
      state: raw.state,
      city: raw.city,
      descriptionHtml: raw.description,
      employmentTypeText: raw.employment_type,
      workArrangement: raw.telecommuting === true ? 'remote' : null,
      educationText: raw.education,
      experienceText: raw.experience,
      postedAt: raw.published_on || raw.created_at,
      raw: { shortcode: raw.shortcode, department: raw.department, function: raw.function, industry: raw.industry },
    });
  }
}
