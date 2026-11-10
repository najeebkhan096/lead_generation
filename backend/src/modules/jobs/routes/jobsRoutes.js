/**
 * /api/jobs — the Jobs Finder API.
 *
 *   GET    /geo/countries                              countries (+ Worldwide/Remote)
 *   GET    /geo/countries/:code/regions                states / provinces
 *   GET    /geo/countries/:code/regions/:region/cities ?q&limit&offset
 *
 *   GET    /sources                                    sources + status (never keys)
 *   PATCH  /sources/:id                                enable, limits, boards, career pages
 *
 *   GET    /searches            POST /searches         list / create a configuration
 *   POST   /searches/estimate                          how many combinations a draft expands to
 *   GET|PUT|DELETE /searches/:id
 *   POST   /searches/:id/scan                          start a scan (202, runs in the background)
 *
 *   GET    /scans                                      history          GET /scans/active
 *   GET    /scans/:runId  (/progress)                  live progress
 *   POST   /scans/:runId/pause | resume | stop
 *   GET    /scans/:runId/failures
 *
 *   GET    /jobs  (filters, cursor paging)             GET /jobs/export.csv   POST /jobs/export {ids}
 *   GET|PATCH|DELETE /jobs/:id                         POST /jobs/:id/verify  POST /jobs/:id/match
 *
 *   GET    /companies  /companies/:id      GET /stats
 *   GET    /applications  /applications/summary
 *   GET|PUT|DELETE /applications/:jobId
 *   GET|POST /alerts   PUT|DELETE /alerts/:id
 */

import express, { Router } from 'express';
import { asyncHandler as wrap, rateLimit, jobsAuth, requestLogger, errorHandler } from './middleware.js';

export function createJobsRouter({ controllers: c, log, auth = jobsAuth(), limiter = rateLimit({ max: 300, name: 'Jobs API' }), heavyLimiter = rateLimit({ max: 20, name: 'Jobs scan/export', windowMs: 60_000 }) }) {
  const r = Router();
  r.use(requestLogger(log));
  r.use(limiter);
  r.use(express.json({ limit: '1mb' })); // CV text for matching is the largest body
  r.use(auth);

  r.get('/geo/countries', wrap(c.search.countries));
  r.get('/geo/countries/:code/regions', wrap(c.search.regions));
  r.get('/geo/countries/:code/regions/:region/cities', wrap(c.search.cities));

  r.get('/sources', wrap(c.search.sources));
  r.patch('/sources/:id', wrap(c.search.updateSource));

  r.get('/searches', wrap(c.search.list));
  r.post('/searches', wrap(c.search.create));
  r.post('/searches/estimate', wrap(c.search.estimate));
  r.get('/searches/:id', wrap(c.search.get));
  r.put('/searches/:id', wrap(c.search.update));
  r.delete('/searches/:id', wrap(c.search.remove));
  r.post('/searches/:id/scan', heavyLimiter, wrap(c.scan.start));

  r.get('/scans', wrap(c.scan.history));
  r.get('/scans/active', wrap(c.scan.active));
  r.get('/scans/:runId', wrap(c.scan.progress));
  r.get('/scans/:runId/progress', wrap(c.scan.progress));
  r.get('/scans/:runId/failures', wrap(c.scan.failures));
  r.post('/scans/:runId/pause', wrap(c.scan.pause));
  r.post('/scans/:runId/resume', wrap(c.scan.resume));
  r.post('/scans/:runId/stop', wrap(c.scan.stop));

  r.get('/jobs', wrap(c.job.list));
  r.get('/jobs/export.csv', heavyLimiter, wrap(c.job.exportFiltered));
  r.post('/jobs/export', heavyLimiter, wrap(c.job.exportSelected));
  r.get('/jobs/:id', wrap(c.job.get));
  r.patch('/jobs/:id', wrap(c.job.patch));
  r.delete('/jobs/:id', wrap(c.job.remove));
  r.post('/jobs/:id/verify', heavyLimiter, wrap(c.job.verify));
  r.post('/jobs/:id/match', wrap(c.job.match));

  r.get('/companies', wrap(c.job.companies));
  r.get('/companies/:id', wrap(c.job.company));
  r.get('/stats', wrap(c.job.stats));

  r.get('/applications', wrap(c.job.applications));
  r.get('/applications/summary', wrap(c.job.applicationSummary));
  r.get('/applications/:jobId', wrap(c.job.application));
  r.put('/applications/:jobId', wrap(c.job.saveApplication));
  r.delete('/applications/:jobId', wrap(c.job.removeApplication));

  r.get('/alerts', wrap(c.job.alerts));
  r.post('/alerts', wrap(c.job.createAlert));
  r.put('/alerts/:id', wrap(c.job.updateAlert));
  r.delete('/alerts/:id', wrap(c.job.removeAlert));

  r.use((_req, res) => res.status(404).json({ error: 'Not found', code: 'NOT_FOUND' }));
  r.use(errorHandler(log));
  return r;
}
