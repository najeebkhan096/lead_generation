/**
 * The contract every job source implements.
 *
 * A *search query* (one combination of the search hierarchy) is:
 *
 *   {
 *     country:  { code: 'US', name: 'United States' },   // code 'WW' = worldwide/remote
 *     state:    'California' | null,
 *     city:     'Los Angeles' | null,
 *     remoteOnly: boolean,        // country-level remote search (no state/city)
 *     title:    'Flutter Developer',
 *     keywords: ['dart'],         // extra terms that must appear
 *     filters:  { experienceLevel, employmentType, workArrangement,
 *                 salaryMin, salaryMax, postedWithinDays },
 *   }
 *
 * An adapter provides, via the template below:
 *
 *   meta               who it is (id, name, type, limits, terms URL)
 *   isConfigured()     has everything it needs (API key, board list)?
 *   supports(query)    can it answer this combination at all?
 *   fetchPage(q, n)    ONE request: { items: raw[], hasMore }  -> pagination
 *   normalize(raw, q)  raw -> buildJob(...)  -> the normalized shape
 *   getJobDetails(ref) re-read one posting: { found: true|false|null, job? }
 *                      `false` only on a definitive "gone"; `null` = unknown
 *
 * `search()` is the shared loop around those: paging, record isolation (a
 * malformed record is skipped, not fatal) and request accounting. Any
 * request goes through `this.getJson/postJson`, which apply the source's
 * rate limit and daily budget and the shared timeout/retry policy.
 */

import { SourceError } from '../utils/errors.js';
import { silentLogger } from '../utils/logger.js';
import { TtlCache } from '../utils/ttlCache.js';

export class JobSourceAdapter {
  /** Subclasses override. */
  static meta = {
    id: 'base',
    name: 'Base',
    type: 'api', // api | ats | feed | career
    homepage: null,
    termsUrl: null,
    requiresKey: false,
    countries: '*', // '*' or an array of ISO codes
    remoteOnly: false,
    defaultLimits: { perMinute: 30, perDay: 1000, maxConcurrent: 2 },
    defaultMaxPages: 3,
    description: '',
  };

  /**
   * @param {object} deps
   * @param {ReturnType<import('../utils/http.js').createHttpClient>} deps.http
   * @param {ReturnType<import('../utils/sourceGate.js').createSourceGate>} deps.gate
   * @param {object} [deps.settings]  stored per-source config (boards, careerPages, maxPages …)
   * @param {Record<string,string|undefined>} [deps.env]
   */
  constructor({ http, gate, log = silentLogger, settings = {}, env = process.env, cache = new TtlCache(), now = () => new Date() } = {}) {
    this.http = http;
    this.gate = gate;
    this.log = log;
    this.settings = settings || {};
    this.env = env;
    this.cache = cache;
    this.now = now;
  }

  get id() {
    return this.constructor.meta.id;
  }

  get meta() {
    return this.constructor.meta;
  }

  /** True when the source has the credentials/configuration it needs. */
  isConfigured() {
    return true;
  }

  /** Tells the operator what is missing when [isConfigured] is false. */
  configurationHint() {
    return null;
  }

  /** Can this source answer [query]? Used to skip pointless requests. */
  supports(query) {
    const { countries, remoteOnly } = this.meta;
    if (remoteOnly && !(query.remoteOnly || query.country?.code === 'WW')) return false;
    if (countries === '*' || query.country?.code === 'WW') return true;
    return countries.includes(query.country?.code);
  }

  /* eslint-disable no-unused-vars */
  async fetchPage(query, page) {
    throw new Error(`${this.id}: fetchPage not implemented`);
  }

  normalize(raw, query) {
    throw new Error(`${this.id}: normalize not implemented`);
  }

  /** Re-reads one posting. Unknown by default: callers must not treat it as "gone". */
  async getJobDetails(ref) {
    return { found: null, job: null };
  }
  /* eslint-enable no-unused-vars */

  /** First page number the source's pagination uses. */
  get firstPage() {
    return 1;
  }

  /**
   * @returns {Promise<{jobs: object[], pages: number, skipped: number, truncated: boolean}>}
   * @throws {SourceError}  when the source itself failed on the first page
   */
  async search(query, { maxPages, maxResults = 200 } = {}) {
    if (!this.isConfigured()) {
      throw new SourceError('not_configured', this.configurationHint() || `${this.id} is not configured`, { retryable: false, source: this.id });
    }
    const pageLimit = Math.max(1, maxPages ?? this.settings.maxPages ?? this.meta.defaultMaxPages);
    const jobs = [];
    let pages = 0;
    let skipped = 0;
    let truncated = false;

    for (let page = this.firstPage; page < this.firstPage + pageLimit; page++) {
      let result;
      try {
        result = await this.fetchPage(query, page);
      } catch (err) {
        // A later page failing keeps what the earlier pages found.
        if (pages > 0 && !(err instanceof SourceError && (err.kind === 'quota' || err.kind === 'auth'))) {
          this.log.warn('later page failed; keeping earlier pages', { source: this.id, page, error: err });
          truncated = true;
          break;
        }
        err.source ??= this.id;
        throw err;
      }
      pages += 1;
      for (const raw of result.items) {
        try {
          const job = this.normalize(raw, query);
          if (job) jobs.push(job);
          else skipped += 1;
        } catch (err) {
          skipped += 1;
          this.log.warn('record skipped', { source: this.id, error: err });
        }
      }
      if (jobs.length >= maxResults) {
        truncated = result.hasMore || jobs.length > maxResults;
        jobs.length = Math.min(jobs.length, maxResults);
        break;
      }
      if (!result.hasMore) break;
      if (page === this.firstPage + pageLimit - 1) truncated = true;
    }
    return { jobs, pages, skipped, truncated };
  }

  // ------------------------------------------------------------- HTTP helpers
  getJson(url, opts) {
    return this.gate.run(() => this.http.getJson(url, opts));
  }

  postJson(url, payload, opts) {
    return this.gate.run(() => this.http.postJson(url, payload, opts));
  }

  getText(url, opts) {
    return this.gate.run(() => this.http.getText(url, opts));
  }

  /** Public description of the source for the API (never includes secrets). */
  describe() {
    const { id, name, type, homepage, termsUrl, requiresKey, countries, remoteOnly, description } = this.meta;
    return {
      id,
      name,
      type,
      homepage,
      termsUrl,
      requiresKey,
      countries,
      remoteOnly,
      description,
      configured: this.isConfigured(),
      configurationHint: this.isConfigured() ? null : this.configurationHint(),
    };
  }
}
