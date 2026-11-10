/**
 * Remotive public API — https://remotive.com/api-documentation (no key)
 *
 *   GET https://remotive.com/api/remote-jobs
 *
 * Remotive's terms (from the API's own legal notice): link back to the
 * Remotive URL AND credit Remotive as the source; don't resubmit its jobs to
 * other job sites; ask for the data a few times a day at most (they advise 4).
 * Accordingly: `sourceUrl` is the Remotive page, the source is always shown as
 * "Remotive", `applyUrl` is left null (their page is where applying starts),
 * the daily budget is 4 requests, and the one response is cached for hours.
 *
 * As observed on 2026-11-07 the public endpoint returns only the 12 newest
 * jobs and ignores `search`/`category`, so everything is filtered here.
 */

import { JobSourceAdapter } from './baseAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';
import { jobMatchesQuery } from '../utils/match.js';

const URL_ALL = 'https://remotive.com/api/remote-jobs';
const TTL_MS = 6 * 3_600_000;
const TYPES = { full_time: 'full_time', part_time: 'part_time', contract: 'contract', freelance: 'freelance', internship: 'internship' };

export class RemotiveAdapter extends JobSourceAdapter {
  static meta = {
    id: 'remotive',
    name: 'Remotive',
    type: 'feed',
    homepage: 'https://remotive.com',
    termsUrl: 'https://remotive.com/api-documentation',
    requiresKey: false,
    countries: '*',
    remoteOnly: true,
    defaultLimits: { perMinute: 2, perDay: 4, maxConcurrent: 1 },
    defaultMaxPages: 1,
    description: 'Remote jobs feed. Remote-only; the free endpoint currently returns just the 12 newest jobs, delayed by 24h. Jobs must be credited to and linked back to Remotive.',
  };

  async feed() {
    return this.cache.getOrLoad(
      'remotive:feed',
      async () => {
        const data = await this.getJson(URL_ALL);
        if (!data || !Array.isArray(data.jobs)) throw new SourceError('parse', 'Unexpected Remotive response', { retryable: false, source: this.id });
        return data.jobs;
      },
      this.settings.feedTtlMs ?? TTL_MS,
    );
  }

  toJob(raw) {
    return buildJob({
      source: this.id,
      sourceJobId: raw.id,
      sourceUrl: raw.url,
      applyUrl: null,
      title: raw.title,
      companyName: raw.company_name,
      locationText: raw.candidate_required_location,
      workArrangement: 'remote',
      descriptionHtml: raw.description,
      employmentType: TYPES[raw.job_type] || null,
      postedAt: raw.publication_date,
      salaryText: raw.salary,
      tags: raw.tags || [],
      raw: { id: raw.id, category: raw.category, tags: raw.tags, candidate_required_location: raw.candidate_required_location },
    });
  }

  async search(query, { maxResults = 200 } = {}) {
    const raws = await this.feed();
    let skipped = 0;
    const jobs = [];
    for (const raw of raws) {
      const job = this.toJob(raw);
      if (!job) skipped += 1;
      else if (jobMatchesQuery(job, { ...query, remoteOnly: true })) jobs.push(job);
    }
    return { jobs: jobs.slice(0, maxResults), pages: 1, skipped, truncated: jobs.length > maxResults };
  }
}
