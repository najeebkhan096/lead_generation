/**
 * Greenhouse public job boards — https://developers.greenhouse.io/job-board.html
 * (no key; read-only public API for boards the company has published).
 *
 *   GET https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true
 */

import { BoardAdapter } from './boardAdapter.js';
import { buildJob } from './buildJob.js';
import { SourceError } from '../utils/errors.js';

const API = 'https://boards-api.greenhouse.io/v1/boards';

export class GreenhouseAdapter extends BoardAdapter {
  static meta = {
    id: 'greenhouse',
    name: 'Greenhouse',
    type: 'ats',
    homepage: 'https://www.greenhouse.com',
    termsUrl: 'https://developers.greenhouse.io/job-board.html',
    requiresKey: false,
    countries: '*',
    remoteOnly: false,
    defaultLimits: { perMinute: 60, perDay: 2000, maxConcurrent: 2 },
    defaultMaxPages: 1,
    description: 'Public job boards of companies that use Greenhouse. Add the board tokens (the last part of boards.greenhouse.io/<token>) to read.',
  };

  async loadBoard(board) {
    const data = await this.getJson(`${API}/${encodeURIComponent(board.id)}/jobs`, { query: { content: 'true' } });
    if (!data || !Array.isArray(data.jobs)) throw new SourceError('parse', 'Unexpected Greenhouse response', { retryable: false, source: this.id });
    let name = board.name;
    if (!name) {
      // The job objects carry `company_name`; only fall back to the board endpoint when there are none.
      name = data.jobs.find((j) => j.company_name)?.company_name || null;
    }
    return { company: { name: name || board.id, website: board.website }, items: data.jobs };
  }

  toJob(raw, board, company) {
    const pay = Array.isArray(raw.pay_input_ranges) ? raw.pay_input_ranges[0] : null;
    return buildJob({
      source: this.id,
      sourceJobId: raw.id,
      sourceUrl: raw.absolute_url,
      applyUrl: raw.absolute_url,
      sourceRef: { board: board.id },
      title: raw.title,
      companyName: raw.company_name || company.name,
      companyWebsite: company.website,
      locationText: raw.location?.name,
      descriptionHtml: raw.content,
      postedAt: raw.first_published,
      sourceUpdatedAt: raw.updated_at,
      deadlineAt: raw.application_deadline,
      salaryMin: pay?.min_cents != null ? pay.min_cents / 100 : null,
      salaryMax: pay?.max_cents != null ? pay.max_cents / 100 : null,
      salaryCurrency: pay?.currency_type,
      raw: { id: raw.id, internal_job_id: raw.internal_job_id, requisition_id: raw.requisition_id, departments: raw.departments?.map((d) => d.name), offices: raw.offices?.map((o) => o.name), updated_at: raw.updated_at },
    });
  }

  async getJobDetails(ref) {
    const board = ref.sourceRef?.board;
    if (!board) return { found: null, job: null };
    try {
      const raw = await this.getJson(`${API}/${encodeURIComponent(board)}/jobs/${encodeURIComponent(ref.sourceJobId)}`);
      const job = this.toJob(raw, { id: board, name: null, website: null }, { name: raw.company_name || board, website: null });
      return { found: true, job };
    } catch (err) {
      // 404 is Greenhouse saying the posting is closed — the one definitive signal.
      if (err instanceof SourceError && err.kind === 'not_found') return { found: false, job: null };
      throw err;
    }
  }
}
