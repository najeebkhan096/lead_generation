/**
 * Jooble REST API — https://jooble.org/api/about (free key)
 *
 *   POST https://jooble.org/api/{key}   { keywords, location, page, ResultOnPage, … }
 *
 * Jooble searches worldwide (it is the source that covers Qatar, the UAE and
 * Saudi Arabia here). It returns a snippet and its own link, so `applyUrl` is
 * left null and the description is flagged truncated.
 *
 * NOTE: the request/response shape follows Jooble's published API
 * description; the adapter has been tested against fixtures of that shape,
 * not against the live API (no key was available when it was written).
 */

import { JobSourceAdapter } from './baseAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';
import { htmlToText } from '../utils/text.js';
import { locationText, searchPhrase } from '../utils/query.js';

const API = 'https://jooble.org/api';
const PER_PAGE = 50;

export class JoobleAdapter extends JobSourceAdapter {
  static meta = {
    id: 'jooble',
    name: 'Jooble',
    type: 'api',
    homepage: 'https://jooble.org',
    termsUrl: 'https://jooble.org/api/about',
    requiresKey: true,
    countries: '*',
    remoteOnly: false,
    defaultLimits: { perMinute: 20, perDay: 300, maxConcurrent: 2 },
    defaultMaxPages: 2,
    description: 'Official Jooble API. Worldwide coverage, including Qatar, UAE and Saudi Arabia. Needs JOOBLE_API_KEY.',
  };

  isConfigured() {
    return Boolean(this.env.JOOBLE_API_KEY);
  }

  configurationHint() {
    return 'Set JOOBLE_API_KEY in the backend environment (request a key at jooble.org/api/about).';
  }

  async fetchPage(query, page) {
    const f = query.filters || {};
    const body = {
      keywords: searchPhrase(query, { withRemote: true }),
      location: locationText(query),
      page: String(page),
      ResultOnPage: String(PER_PAGE),
    };
    if (f.salaryMin) body.salary = String(f.salaryMin);
    if (f.postedWithinDays) body.datecreatedfrom = new Date(this.now().getTime() - f.postedWithinDays * 86_400_000).toISOString().slice(0, 10);
    const data = await this.postJson(`${API}/${encodeURIComponent(this.env.JOOBLE_API_KEY)}`, body);
    if (!data || !Array.isArray(data.jobs)) throw new SourceError('parse', 'Unexpected Jooble response', { retryable: false, source: this.id });
    const hasMore = data.jobs.length >= PER_PAGE && page * PER_PAGE < (Number(data.totalCount) || 0);
    return { items: data.jobs, hasMore };
  }

  normalize(raw, query) {
    return buildJob({
      source: this.id,
      sourceJobId: raw.id,
      sourceUrl: raw.link,
      applyUrl: null,
      title: htmlToText(raw.title).replace(/\s+/g, ' '),
      companyName: raw.company,
      locationText: raw.location,
      // The search was scoped to this country, so an unparsed location is still inside it.
      countryCode: query.country?.code === 'WW' || query.remoteOnly ? null : query.country?.code,
      description: htmlToText(raw.snippet),
      descriptionTruncatedBySource: true,
      employmentTypeText: raw.type,
      postedAt: raw.updated,
      salaryText: raw.salary,
      raw: { id: raw.id, source: raw.source, salary: raw.salary, type: raw.type },
    });
  }
}
