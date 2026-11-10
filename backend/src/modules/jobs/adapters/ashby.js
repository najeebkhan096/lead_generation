/**
 * Ashby public job boards — https://developers.ashbyhq.com/docs/public-job-posting-api
 *
 *   GET https://api.ashbyhq.com/posting-api/job-board/{board}?includeCompensation=true
 */

import { BoardAdapter } from './boardAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';
import { geoCatalog } from '../geo/geoCatalog.js';

const EMPLOYMENT = { fulltime: 'full_time', parttime: 'part_time', intern: 'internship', contract: 'contract', temporary: 'temporary' };
const ARRANGEMENT = { remote: 'remote', hybrid: 'hybrid', onsite: 'onsite' };
const prettify = (slug) => slug.replace(/[-_.]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

/** "1 YEAR" / "1 MONTH" / "1 HOUR" -> year | month | hour. */
function periodOf(interval) {
  const s = String(interval || '').toLowerCase();
  for (const p of ['year', 'month', 'week', 'day', 'hour']) if (s.includes(p)) return p;
  return null;
}

export class AshbyAdapter extends BoardAdapter {
  static meta = {
    id: 'ashby',
    name: 'Ashby',
    type: 'ats',
    homepage: 'https://www.ashbyhq.com',
    termsUrl: 'https://developers.ashbyhq.com/docs/public-job-posting-api',
    requiresKey: false,
    countries: '*',
    remoteOnly: false,
    defaultLimits: { perMinute: 30, perDay: 1000, maxConcurrent: 1 },
    defaultMaxPages: 1,
    description: 'Public job boards of companies that use Ashby. Add the board name (jobs.ashbyhq.com/<board>).',
  };

  async loadBoard(board) {
    const data = await this.getJson(`https://api.ashbyhq.com/posting-api/job-board/${encodeURIComponent(board.id)}`, { query: { includeCompensation: 'true' } });
    if (!data || !Array.isArray(data.jobs)) throw new SourceError('parse', 'Unexpected Ashby response', { retryable: false, source: this.id });
    return { company: { name: board.name || prettify(board.id), website: board.website }, items: data.jobs };
  }

  toJob(raw, board, company) {
    if (raw.isListed === false) return null; // unlisted postings are not public
    const addr = raw.address?.postalAddress || {};
    const component = (raw.compensation?.summaryComponents || []).find((c) => String(c.compensationType).toLowerCase() === 'salary');
    // `addressCountry` is sometimes a name, sometimes an ISO code.
    const countryCode = addr.addressCountry ? geoCatalog.findCountryCode(addr.addressCountry) : null;
    return buildJob({
      source: this.id,
      sourceJobId: raw.id,
      sourceUrl: raw.jobUrl,
      applyUrl: raw.applyUrl || raw.jobUrl,
      sourceRef: { board: board.id },
      title: raw.title,
      companyName: company.name,
      companyWebsite: company.website,
      locationText: raw.location,
      countryCode,
      country: countryCode ? null : addr.addressCountry,
      state: addr.addressRegion,
      city: addr.addressLocality,
      descriptionHtml: raw.descriptionHtml,
      description: raw.descriptionHtml ? undefined : raw.descriptionPlain,
      employmentType: EMPLOYMENT[String(raw.employmentType || '').toLowerCase()] || null,
      workArrangement: raw.isRemote ? 'remote' : ARRANGEMENT[String(raw.workplaceType || '').toLowerCase()] || null,
      postedAt: raw.publishedAt,
      salaryMin: component?.minValue,
      salaryMax: component?.maxValue,
      salaryCurrency: component?.currencyCode,
      salaryPeriod: periodOf(component?.interval),
      raw: { id: raw.id, department: raw.department, team: raw.team, secondaryLocations: raw.secondaryLocations, compensation: raw.compensation?.compensationTierSummary },
    });
  }
}
