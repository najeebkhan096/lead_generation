/**
 * Adzuna Jobs API — https://developer.adzuna.com/ (free key: app id + app key)
 *
 *   GET https://api.adzuna.com/v1/api/jobs/{country}/search/{page}
 *       ?app_id&app_key&results_per_page&what&where&…
 *
 * Adzuna answers per country (no Gulf states, no worldwide), returns a short
 * description snippet and links through its own redirect URL — which is why
 * `applyUrl` is left null (the redirect is not the employer's page) and the
 * description is flagged as truncated by the source.
 */

import { JobSourceAdapter } from './baseAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';
import { htmlToText } from '../utils/text.js';
import { searchPhrase } from '../utils/query.js';

const API = 'https://api.adzuna.com/v1/api/jobs';
const PER_PAGE = 50;

/** ISO country -> [adzuna path segment, currency of its salaries]. */
export const ADZUNA_COUNTRIES = {
  US: ['us', 'USD'], GB: ['gb', 'GBP'], CA: ['ca', 'CAD'], DE: ['de', 'EUR'], AT: ['at', 'EUR'], BE: ['be', 'EUR'],
  FR: ['fr', 'EUR'], ES: ['es', 'EUR'], IT: ['it', 'EUR'], NL: ['nl', 'EUR'], AU: ['au', 'AUD'], NZ: ['nz', 'NZD'],
  BR: ['br', 'BRL'], CH: ['ch', 'CHF'], IN: ['in', 'INR'], MX: ['mx', 'MXN'], PL: ['pl', 'PLN'], SG: ['sg', 'SGD'], ZA: ['za', 'ZAR'],
};

const CONTRACT = { permanent: 'permanent', contract: 'contract' };
const TIME = { full_time: 'full_time', part_time: 'part_time' };

export class AdzunaAdapter extends JobSourceAdapter {
  static meta = {
    id: 'adzuna',
    name: 'Adzuna',
    type: 'api',
    homepage: 'https://www.adzuna.com',
    termsUrl: 'https://developer.adzuna.com/overview',
    requiresKey: true,
    countries: Object.keys(ADZUNA_COUNTRIES),
    remoteOnly: false,
    defaultLimits: { perMinute: 20, perDay: 250, maxConcurrent: 2 },
    defaultMaxPages: 2,
    description: 'Official Adzuna search API. Covers US, Canada, Germany and other countries; not Qatar, UAE or Saudi Arabia. Needs ADZUNA_APP_ID and ADZUNA_APP_KEY.',
  };

  isConfigured() {
    return Boolean(this.env.ADZUNA_APP_ID && this.env.ADZUNA_APP_KEY);
  }

  configurationHint() {
    return 'Set ADZUNA_APP_ID and ADZUNA_APP_KEY in the backend environment (free keys: developer.adzuna.com).';
  }

  supports(query) {
    // Adzuna has no worldwide/remote endpoint; a country-level remote search runs in the country.
    return Boolean(ADZUNA_COUNTRIES[query.country?.code]);
  }

  async fetchPage(query, page) {
    const [segment] = ADZUNA_COUNTRIES[query.country.code];
    const f = query.filters || {};
    const params = {
      app_id: this.env.ADZUNA_APP_ID,
      app_key: this.env.ADZUNA_APP_KEY,
      results_per_page: PER_PAGE,
      what: searchPhrase(query, { withRemote: query.remoteOnly }),
      where: query.remoteOnly ? undefined : [query.city, query.state].filter((v, i, a) => v && (i === 0 || v !== a[i - 1])).join(', ') || undefined,
      salary_min: f.salaryMin || undefined,
      salary_max: f.salaryMax || undefined,
      max_days_old: f.postedWithinDays || undefined,
      full_time: f.employmentType === 'full_time' ? 1 : undefined,
      part_time: f.employmentType === 'part_time' ? 1 : undefined,
      contract: f.employmentType === 'contract' ? 1 : undefined,
      permanent: f.employmentType === 'permanent' ? 1 : undefined,
      'content-type': 'application/json',
    };
    const data = await this.getJson(`${API}/${segment}/search/${page}`, { query: params });
    if (!data || !Array.isArray(data.results)) throw new SourceError('parse', 'Unexpected Adzuna response', { retryable: false, source: this.id });
    const hasMore = data.results.length >= PER_PAGE && page * PER_PAGE < (Number(data.count) || 0);
    return { items: data.results, hasMore };
  }

  normalize(raw, query) {
    const [, currency] = ADZUNA_COUNTRIES[query.country.code];
    const area = Array.isArray(raw.location?.area) ? raw.location.area : [];
    // Adzuna fills `salary_min/max` with *predicted* figures when the ad has none;
    // those are estimates, not what the employer published, so they are not stored.
    const predicted = String(raw.salary_is_predicted) === '1';
    const hasSalary = !predicted && (raw.salary_min || raw.salary_max);
    return buildJob({
      source: this.id,
      sourceJobId: raw.id,
      sourceUrl: raw.redirect_url,
      applyUrl: null,
      title: htmlToText(raw.title).replace(/\s+/g, ' '),
      companyName: raw.company?.display_name,
      locationText: raw.location?.display_name,
      // Adzuna's `area` is [country, state, county, city] — structured, so trusted.
      countryCode: query.country.code,
      state: area[1] || null,
      city: area.length > 3 ? area[area.length - 1] : null,
      description: htmlToText(raw.description),
      descriptionTruncatedBySource: true,
      employmentType: TIME[raw.contract_time] || CONTRACT[raw.contract_type] || null,
      postedAt: raw.created,
      salaryMin: hasSalary ? raw.salary_min : null,
      salaryMax: hasSalary ? raw.salary_max : null,
      salaryCurrency: hasSalary ? currency : null,
      salaryPeriod: hasSalary ? 'year' : null,
      tags: [],
      raw: { id: raw.id, category: raw.category?.label, area, salary_is_predicted: raw.salary_is_predicted, adref: raw.adref },
    });
  }
}
