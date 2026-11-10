/**
 * Base for sources that publish a company's whole job board (Greenhouse,
 * Lever, Ashby, Workable). They have no "search" endpoint, so:
 *
 *   - the operator lists the company boards to read (`settings.boards`),
 *   - each board is fetched whole and cached for a few minutes, so a scan
 *     with thousands of combinations makes one request per board, not one
 *     per combination,
 *   - the cached postings are filtered against the combination here.
 *
 * One board failing (wrong token, outage) is reported as a warning; the
 * source fails only if every board failed.
 */

import { JobSourceAdapter } from './baseAdapter.js';
import { SourceError } from '../utils/errors.js';
import { jobMatchesQuery } from '../utils/match.js';

const BOARD_TTL_MS = 15 * 60_000;

export class BoardAdapter extends JobSourceAdapter {
  /** @returns {{id: string, name: string|null, website: string|null, region: string|null}[]} */
  boards() {
    const list = Array.isArray(this.settings.boards) ? this.settings.boards : [];
    const seen = new Set();
    const out = [];
    for (const entry of list) {
      const obj = typeof entry === 'string' ? { id: entry } : entry || {};
      const id = String(obj.id ?? obj.token ?? obj.slug ?? obj.company ?? '').trim();
      if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$/.test(id) || seen.has(id.toLowerCase())) continue;
      seen.add(id.toLowerCase());
      out.push({ id, name: obj.name || null, website: obj.website || null, region: obj.region || null });
    }
    return out;
  }

  isConfigured() {
    return this.boards().length > 0;
  }

  configurationHint() {
    return `Add at least one ${this.meta.name} board token under this source's "boards" setting.`;
  }

  /** Subclass: fetch one board -> { company: {name, website}, items: raw[] }. */
  // eslint-disable-next-line no-unused-vars
  async loadBoard(board) {
    throw new Error(`${this.id}: loadBoard not implemented`);
  }

  /** Subclass: raw posting -> buildJob(...) result (or null). */
  // eslint-disable-next-line no-unused-vars
  toJob(raw, board, company) {
    throw new Error(`${this.id}: toJob not implemented`);
  }

  async board(board) {
    return this.cache.getOrLoad(`${this.id}:${board.id.toLowerCase()}`, () => this.loadBoard(board), this.settings.boardTtlMs ?? BOARD_TTL_MS);
  }

  /** Every posting of every configured board, normalized (not yet filtered). */
  async collect() {
    const boards = this.boards();
    const jobs = [];
    const warnings = [];
    let skipped = 0;
    let failures = 0;
    let lastError = null;
    for (const board of boards) {
      try {
        const data = await this.board(board);
        for (const raw of data.items) {
          try {
            const job = this.toJob(raw, board, data.company);
            if (job) jobs.push(job);
            else skipped += 1;
          } catch (err) {
            skipped += 1;
            this.log.warn('record skipped', { source: this.id, board: board.id, error: err });
          }
        }
      } catch (err) {
        failures += 1;
        lastError = err;
        // Out of budget or refused: no point trying the remaining boards.
        if (err instanceof SourceError && (err.kind === 'quota' || err.kind === 'rate_limited')) {
          warnings.push({ board: board.id, kind: err.kind, message: err.message });
          break;
        }
        warnings.push({ board: board.id, kind: err.kind || 'error', message: err.message });
        this.log.warn('board failed', { source: this.id, board: board.id, error: err });
      }
    }
    if (failures > 0 && failures === boards.length && lastError) {
      lastError.source ??= this.id;
      throw lastError;
    }
    return { jobs, warnings, skipped };
  }

  async search(query, { maxResults = 200 } = {}) {
    if (!this.isConfigured()) {
      throw new SourceError('not_configured', this.configurationHint(), { retryable: false, source: this.id });
    }
    const { jobs: all, warnings, skipped } = await this.collect();
    const matched = all.filter((job) => jobMatchesQuery(job, query));
    return {
      jobs: matched.slice(0, maxResults),
      pages: this.boards().length,
      skipped,
      truncated: matched.length > maxResults,
      warnings,
    };
  }

  /** Re-reads one posting through the cached board; subclasses may override with a direct call. */
  async getJobDetails(ref) {
    const board = this.boards().find((b) => b.id.toLowerCase() === String(ref.sourceRef?.board || '').toLowerCase());
    if (!board) return { found: null, job: null };
    this.cache.clear();
    const data = await this.board(board);
    const job = data.items.map((raw) => this.toJob(raw, board, data.company)).find((j) => j && j.sourceJobId === String(ref.sourceJobId));
    // The whole board was read successfully, so a missing posting is a real "gone".
    return job ? { found: true, job } : { found: false, job: null };
  }
}
