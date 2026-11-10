/** Jobs, companies, statistics, export, applications, alerts and matching. */

import { parseJobFilters, parseJobPatch, parseIdList, parseApplication, parseAlert } from '../validators/jobs.js';
import { q } from '../validators/validate.js';
import { csvHeader, jobCsvRow } from '../utils/csv.js';
import { notFound, invalid } from '../utils/errors.js';
import { APPLICATION_STAGES } from '../models/constants.js';

const EXPORT_LIMIT = 20_000;
const stageForState = { saved: 'saved', applied: 'applied', rejected: 'rejected', withdrawn: 'withdrawn' };

export function createJobController({ jobStore, companyStore, applicationStore, alertStore, statsService, verifyService, matcher, registry, log }) {
  async function exportRows(res, rows) {
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="jobs-${new Date().toISOString().slice(0, 10)}.csv"`);
    res.write('﻿'); // BOM: Excel reads UTF-8 correctly
    res.write(`${csvHeader()}\r\n`);
    let n = 0;
    for await (const job of rows) {
      res.write(`${jobCsvRow(job)}\r\n`);
      n += 1;
    }
    res.end();
    return n;
  }

  return {
    // ----------------------------------------------------------------- jobs
    async list(req, res) {
      res.json(await jobStore.list(parseJobFilters(req.query)));
    },

    async get(req, res) {
      res.json({ job: await jobStore.getDetail(req.params.id) });
    },

    async patch(req, res) {
      const body = parseJobPatch(req.body);
      const id = req.params.id;
      if (!(await jobStore.get(id))) throw notFound('Job not found');
      if (body.userState) {
        // The application tracker is the single source of truth for what the user did with a job.
        if (body.userState === 'new') {
          await applicationStore.remove(id).catch((e) => { if (e.status !== 404) throw e; });
        } else {
          await applicationStore.upsert(id, { stage: stageForState[body.userState] });
        }
      }
      if (body.status) await jobStore.setStatus(id, body.status, { source: 'manual', reason: 'set by user' });
      if (body.notes !== undefined) await jobStore.patch(id, { notes: body.notes });
      statsService.invalidate();
      res.json({ job: await jobStore.getDetail(id) });
    },

    async remove(req, res) {
      await jobStore.remove(req.params.id);
      await applicationStore.remove(req.params.id).catch(() => {});
      statsService.invalidate();
      res.json({ deleted: true, id: req.params.id });
    },

    async verify(req, res) {
      const result = await verifyService.verifyJob(req.params.id);
      statsService.invalidate();
      res.json({ verification: result, job: await jobStore.getDetail(req.params.id) });
    },

    async match(req, res) {
      const snap = await jobStore.get(req.params.id);
      if (!snap) throw notFound('Job not found');
      res.json({ match: await matcher.match(req.body?.cvText, snap.data(), { provider: req.body?.provider }) });
    },

    // --------------------------------------------------------------- export
    /** GET /jobs/export.csv?<same filters as the list> — everything that matches, paged internally. */
    async exportFiltered(req, res) {
      const filters = parseJobFilters(req.query);
      async function* rows() {
        let cursor;
        let sent = 0;
        do {
          const page = await jobStore.list({ ...filters, limit: 100, cursor });
          for (const job of page.items) {
            if (sent++ >= EXPORT_LIMIT) return;
            yield job;
          }
          cursor = page.nextCursor;
        } while (cursor);
      }
      const n = await exportRows(res, rows());
      log.info('jobs exported', { rows: n, mode: 'filtered' });
    },

    /** POST /jobs/export { ids } — the jobs ticked in the explorer. */
    async exportSelected(req, res) {
      const ids = parseIdList(req.body, 1000);
      async function* rows() {
        for (const id of ids) {
          const snap = await jobStore.get(id);
          if (snap) yield { id: snap.id, ...snap.data() };
        }
      }
      const n = await exportRows(res, rows());
      log.info('jobs exported', { rows: n, mode: 'selected' });
    },

    // ------------------------------------------------------------ companies
    async companies(req, res) {
      res.json(await companyStore.list({ limit: q.int(req.query, 'limit'), cursor: q.str(req.query, 'cursor'), q: q.str(req.query, 'q') }));
    },

    async company(req, res) {
      res.json({ company: await companyStore.get(req.params.id) });
    },

    // ---------------------------------------------------------------- stats
    async stats(req, res) {
      res.json(await statsService.overview({ force: req.query.refresh === '1' }));
    },

    // --------------------------------------------------------- applications
    async applications(req, res) {
      const stage = q.str(req.query, 'stage');
      if (stage && !APPLICATION_STAGES.includes(stage)) throw invalid(`stage must be one of ${APPLICATION_STAGES.join(', ')}`);
      res.json(await applicationStore.list({ stage, limit: q.int(req.query, 'limit'), cursor: q.str(req.query, 'cursor') }));
    },

    async applicationSummary(_req, res) {
      res.json({ byStage: await applicationStore.countsByStage() });
    },

    async application(req, res) {
      res.json({ application: await applicationStore.get(req.params.jobId) });
    },

    async saveApplication(req, res) {
      const fields = parseApplication(req.body, { partial: true });
      const existed = await applicationStore.get(req.params.jobId).then(() => true, () => false);
      const application = await applicationStore.upsert(req.params.jobId, fields);
      statsService.invalidate();
      res.status(existed ? 200 : 201).json({ application });
    },

    async removeApplication(req, res) {
      await applicationStore.remove(req.params.jobId);
      statsService.invalidate();
      res.json({ deleted: true, id: req.params.jobId });
    },

    // --------------------------------------------------------------- alerts
    async alerts(req, res) {
      res.json(await alertStore.list({ limit: q.int(req.query, 'limit'), cursor: q.str(req.query, 'cursor') }));
    },

    async createAlert(req, res) {
      res.status(201).json({ alert: await alertStore.create(parseAlert(req.body, { sourceIds: registry.ids() })) });
    },

    async updateAlert(req, res) {
      res.json({ alert: await alertStore.update(req.params.id, parseAlert(req.body, { sourceIds: registry.ids() })) });
    },

    async removeAlert(req, res) {
      await alertStore.remove(req.params.id);
      res.json({ deleted: true, id: req.params.id });
    },
  };
}
