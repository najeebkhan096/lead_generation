import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { createJobsModule } from '../index.js';
import { FakeFirestore } from '../testing/fakeFirestore.js';
import { sampleJob, waitFor } from '../testing/engineHarness.js';
import { JobSourceAdapter } from '../adapters/baseAdapter.js';
import { silentLogger } from '../utils/logger.js';
import { rateLimit, jobsAuth } from './middleware.js';

/** A real adapter class (so the real registry, gate and settings code run) with scripted results. */
function scriptedAdapter(id, handler, { requiresKey = false } = {}) {
  return class extends JobSourceAdapter {
    static meta = { id, name: id, type: 'api', homepage: null, termsUrl: null, requiresKey, countries: '*', remoteOnly: false, defaultLimits: { perMinute: 6000, perDay: 100000, maxConcurrent: 4 }, defaultMaxPages: 1, description: 'test' };
    isConfigured() {
      return !requiresKey || Boolean(this.env.ALPHA_KEY);
    }
    async search(query) {
      return { jobs: await handler(query), pages: 1, skipped: 0, truncated: false };
    }
  };
}

const jobFor = (q) =>
  sampleJob({
    source: 'alpha',
    sourceJobId: `${q.city}-${q.title}`,
    sourceUrl: `https://alpha.test/${encodeURIComponent(q.city || 'x')}/${encodeURIComponent(q.title)}`,
    applyUrl: `https://careers.acme.test/${encodeURIComponent(q.city || 'x')}/${encodeURIComponent(q.title)}`,
    title: q.title,
    locationText: q.city ? `${q.city}, CA` : 'Remote',
    salaryMin: 100000,
    salaryMax: 140000,
    salaryCurrency: 'USD',
    salaryPeriod: 'year',
  });

let server;
let base;
let jobs;
let db;
const AlphaClass = scriptedAdapter('alpha', async (q) => [jobFor(q)]);

async function api(method, path, body, { raw = false } = {}) {
  const res = await fetch(`${base}/api/jobs${path}`, { method, headers: body ? { 'content-type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined });
  if (raw) return res;
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null, headers: res.headers };
}

before(async () => {
  db = new FakeFirestore();
  jobs = createJobsModule({
    db,
    env: {},
    log: silentLogger,
    registryOptions: { classes: [AlphaClass] },
    engineOptions: { flushMs: 10, heartbeatMs: 30, pausePollMs: 3 },
  });
  const app = express();
  app.use(express.json());
  app.use('/api/jobs', jobs.router);
  await new Promise((r) => {
    server = app.listen(0, '127.0.0.1', r);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((r) => server.close(r));
});

const SEARCH = {
  name: 'Flutter in California',
  countries: [{ code: 'US', level: 'city', regions: ['California'], cities: [{ state: 'California', city: 'Los Angeles' }, { state: 'California', city: 'San Francisco' }] }],
  titles: ['Flutter Developer', 'Senior Flutter Developer'],
  keywords: ['dart'],
  limits: { concurrency: 2 },
};

test('geography: countries, regions and cities come from the catalog', async () => {
  const countries = await api('GET', '/geo/countries');
  assert.equal(countries.status, 200);
  assert.deepEqual(countries.body.countries.map((c) => c.code).sort(), ['AE', 'CA', 'DE', 'QA', 'SA', 'US', 'WW']);
  assert.match(countries.headers.get('cache-control'), /max-age/);

  const regions = await api('GET', '/geo/countries/US/regions');
  assert.equal(regions.body.regions.length, 51);
  assert.equal(regions.body.country.adminLabel, 'State');

  const cities = await api('GET', '/geo/countries/US/regions/California/cities?q=san&limit=5');
  assert.equal(cities.body.cities.length, 5);
  assert.ok(cities.body.total > 5);
  assert.ok(cities.body.cities.every((c) => /san/i.test(c.name)));

  assert.equal((await api('GET', '/geo/countries/XX/regions')).status, 404);
  assert.equal((await api('GET', '/geo/countries/US/regions/Atlantis/cities')).status, 404);
});

test('search validation reports every problem at once with a 422', async () => {
  const bad = await api('POST', '/searches', { name: 'x', countries: [{ code: 'ZZ' }, { code: 'US', level: 'planet', regions: ['Atlantis'] }], titles: [], limits: { concurrency: 99 }, schedule: { timezone: 'Mars/Base' } });
  assert.equal(bad.status, 422);
  assert.equal(bad.body.code, 'VALIDATION_FAILED');
  const fields = bad.body.details.map((d) => d.field);
  for (const f of ['name', 'countries[0].code', 'countries[1].level', 'titles', 'limits']) assert.ok(fields.some((x) => x.startsWith(f)), `expected a problem for ${f}, got ${fields}`);
  assert.ok(fields.includes('schedule.timezone'));
  assert.equal((await api('POST', '/searches', null)).status, 422);
});

test('estimate: the number of combinations is known before any scan starts', async () => {
  const e = await api('POST', '/searches/estimate', { countries: [{ code: 'US', level: 'state' }, { code: 'WW' }], titles: ['A', 'B', 'a '] });
  assert.equal(e.status, 200);
  assert.equal(e.body.titles, 2, 'titles are de-duplicated');
  assert.equal(e.body.locations, 52, '51 states + worldwide');
  assert.equal(e.body.combinations, 104);
  assert.equal(e.body.withinLimit, true);
  const all = await api('POST', '/searches/estimate', { countries: [{ code: 'US', level: 'city' }], titles: ['A'] });
  assert.equal(all.body.combinations, 7515);
});

test('a full journey: create a search, scan it, browse, triage, track, export, delete', async () => {
  // create
  const created = await api('POST', '/searches', SEARCH);
  assert.equal(created.status, 201);
  const searchId = created.body.search.id;
  assert.equal(created.body.search.limits.concurrency, 2);
  assert.equal(created.body.search.limits.maxCombinations, 20000, 'defaults fill in');
  assert.equal((await api('GET', `/searches/${searchId}`)).body.search.name, SEARCH.name);
  const renamed = await api('PUT', `/searches/${searchId}`, { ...SEARCH, name: 'Flutter CA v2' });
  assert.equal(renamed.body.search.name, 'Flutter CA v2');

  // scan (202, background)
  const started = await api('POST', `/searches/${searchId}/scan`);
  assert.equal(started.status, 202);
  const runId = started.body.run.id;
  await waitFor(async () => (await api('GET', `/scans/${runId}/progress`)).body.run.status === 'completed');
  const run = (await api('GET', `/scans/${runId}`)).body.run;
  assert.equal(run.totals.combinations, 4);
  assert.equal(run.jobs.new, 4);
  assert.equal(run.sources.alpha.requests, 4);
  assert.equal((await api('GET', '/scans')).body.items[0].id, runId);
  assert.equal((await api('GET', '/scans/active')).body.runs.length, 0);

  // browse with server-side filters and paging
  const all = await api('GET', '/jobs?limit=2');
  assert.equal(all.body.items.length, 2);
  assert.equal(all.body.total, 4);
  assert.ok(all.body.nextCursor);
  assert.equal(all.body.items[0].description, undefined, 'lists do not carry full descriptions');
  const page2 = await api('GET', `/jobs?limit=2&cursor=${all.body.nextCursor}`);
  assert.equal(page2.body.items.length, 2);
  assert.equal(page2.body.nextCursor, null);
  assert.equal(new Set([...all.body.items, ...page2.body.items].map((j) => j.id)).size, 4);

  const la = await api('GET', '/jobs?country=us&state=California&city=Los%20Angeles');
  assert.equal(la.body.items.length, 2);
  const senior = await api('GET', '/jobs?q=senior&skills=flutter,dart');
  assert.equal(senior.body.items.length, 2);
  assert.equal((await api('GET', '/jobs?salaryMin=150000')).body.items.length, 0);
  assert.equal((await api('GET', '/jobs?salaryMin=120000&salaryCurrency=USD')).body.items.length, 4);
  assert.equal((await api('GET', '/jobs?source=alpha&workArrangement=remote')).body.items.length, 0);
  assert.equal((await api('GET', '/jobs?status=bogus')).status, 422);
  assert.equal((await api('GET', '/jobs?cursor=not-a-cursor')).status, 400);

  // details
  const jobId = all.body.items[0].id;
  const detail = (await api('GET', `/jobs/${jobId}`)).body.job;
  assert.ok(detail.description.length > 100);
  assert.equal(detail.sources[0].source, 'alpha');
  assert.equal(detail.discoveredBy.runId, runId);
  assert.equal((await api('GET', '/jobs/nope')).status, 404);

  // triage through the application tracker
  const saved = await api('PUT', `/applications/${jobId}`, { stage: 'saved' });
  assert.equal(saved.status, 201);
  assert.equal((await api('GET', `/jobs/${jobId}`)).body.job.userState, 'saved');
  const applied = await api('PUT', `/applications/${jobId}`, { stage: 'interview', notes: 'Phone screen Tuesday' });
  assert.equal(applied.status, 200);
  assert.equal(applied.body.application.history.length, 2);
  assert.equal((await api('GET', `/jobs/${jobId}`)).body.job.userState, 'applied');
  assert.equal((await api('GET', '/jobs?userState=applied')).body.items.length, 1);
  assert.equal((await api('GET', '/applications?stage=interview')).body.items.length, 1);
  assert.equal((await api('GET', '/applications/summary')).body.byStage.interview, 1);
  assert.equal((await api('PUT', `/applications/${jobId}`, { stage: 'dancing' })).status, 422);
  assert.equal((await api('PUT', '/applications/nope', { stage: 'saved' })).status, 404);

  // mark expired, then via PATCH userState back to new (clears the application)
  const expired = await api('PATCH', `/jobs/${jobId}`, { status: 'expired' });
  assert.equal(expired.body.job.status, 'expired');
  assert.equal((await api('GET', '/jobs?status=expired')).body.items.length, 1);
  await api('PATCH', `/jobs/${jobId}`, { userState: 'new' });
  assert.equal((await api('GET', `/jobs/${jobId}`)).body.job.userState, 'new');
  assert.equal((await api('GET', `/applications/${jobId}`)).status, 404);
  assert.equal((await api('PATCH', `/jobs/${jobId}`, {})).status, 422);

  // statistics
  const stats = (await api('GET', '/stats?refresh=1')).body;
  assert.equal(stats.jobs.total, 4);
  assert.equal(stats.jobs.expired, 1);
  assert.equal(stats.companies, 1);
  assert.equal(stats.lastScan.id, runId);
  assert.equal(stats.scans.completed, 1);
  assert.equal(stats.scans.successRate, 100);

  // companies
  const companies = (await api('GET', '/companies')).body;
  assert.equal(companies.items.length, 1);
  assert.equal(companies.items[0].jobCount, 4);

  // export
  const csv = await api('GET', '/jobs/export.csv?city=Los%20Angeles', null, { raw: true });
  assert.equal(csv.status, 200);
  assert.match(csv.headers.get('content-type'), /text\/csv/);
  const lines = (await csv.text()).replace(/^﻿/, '').trim().split('\r\n');
  assert.equal(lines.length, 3, 'header + 2 jobs');
  assert.match(lines[0], /^Title,Company,/);
  const picked = await api('POST', '/jobs/export', { ids: [jobId] }, { raw: true });
  assert.equal((await picked.text()).trim().split('\r\n').length, 2);
  assert.equal((await api('POST', '/jobs/export', { ids: [] })).status, 422);

  // delete a job: gone, and a re-scan does not bring it back
  assert.equal((await api('DELETE', `/jobs/${jobId}`)).status, 200);
  assert.equal((await api('GET', `/jobs/${jobId}`)).status, 404);
  const second = await api('POST', `/searches/${searchId}/scan`);
  await waitFor(async () => (await api('GET', `/scans/${second.body.run.id}`)).body.run.status === 'completed');
  assert.equal((await api('GET', '/jobs')).body.total, 3);

  // a search with an active scan can't be deleted; an idle one can
  assert.equal((await api('DELETE', `/searches/${searchId}`)).status, 200);
  assert.equal((await api('GET', `/searches/${searchId}`)).status, 404);
});

test('scan control over HTTP: pause, resume, stop; bad states are conflicts', async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  const SlowClass = scriptedAdapter('alpha', async (q) => {
    await gate;
    return [jobFor(q)];
  });
  const slowDb = new FakeFirestore();
  const slow = createJobsModule({ db: slowDb, env: {}, log: silentLogger, registryOptions: { classes: [SlowClass] }, engineOptions: { flushMs: 10, heartbeatMs: 30, pausePollMs: 3 } });
  const app = express();
  app.use(express.json());
  app.use('/api/jobs', slow.router);
  const srv = await new Promise((r) => {
    const s = app.listen(0, '127.0.0.1', () => r(s));
  });
  const b = `http://127.0.0.1:${srv.address().port}/api/jobs`;
  const call = async (method, path, body) => {
    const res = await fetch(`${b}${path}`, { method, headers: { 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, body: await res.json() };
  };
  try {
    const s = await call('POST', '/searches', { ...SEARCH, limits: { concurrency: 1 } });
    const started = await call('POST', `/searches/${s.body.search.id}/scan`);
    const runId = started.body.run.id;
    assert.equal((await call('POST', `/scans/${runId}/resume`)).status, 409, 'nothing to resume while running');
    assert.equal((await call('POST', `/scans/${runId}/pause`)).body.run.status, 'paused');
    assert.equal((await call('POST', `/scans/${runId}/pause`)).status, 409);
    assert.equal((await call('GET', '/scans/active')).body.runs.length, 1);
    assert.equal((await call('DELETE', `/searches/${s.body.search.id}`)).status, 409, 'active scan blocks deletion');
    assert.equal((await call('POST', `/scans/${runId}/resume`)).body.run.status, 'running');
    assert.equal((await call('POST', `/scans/${runId}/stop`)).body.run.status, 'stopping');
    release();
    await waitFor(async () => (await call('GET', `/scans/${runId}`)).body.run.status === 'stopped');
    assert.equal((await call('POST', `/scans/${runId}/stop`)).status, 409);
    assert.equal((await call('POST', '/scans/nope/stop')).status, 404);
  } finally {
    release();
    await new Promise((r) => srv.close(r));
  }
});

test('sources: configuration is reported without secrets, and can be updated', async () => {
  const list = await api('GET', '/sources');
  assert.equal(list.status, 200);
  const alpha = list.body.sources.find((s) => s.id === 'alpha');
  assert.equal(alpha.configured, true);
  assert.ok(!JSON.stringify(list.body).match(/key|secret|token/i) || !/[A-Za-z0-9]{20,}/.test(JSON.stringify(list.body)));

  const upd = await api('PATCH', '/sources/alpha', { enabled: false, limits: { perDay: 50 } });
  assert.equal(upd.body.source.enabled, false);
  assert.equal(upd.body.source.limits.perDay, 50);
  assert.equal((await api('PATCH', '/sources/alpha', {})).status, 422);
  assert.equal((await api('PATCH', '/sources/missing', { enabled: true })).status, 404);
  await api('PATCH', '/sources/alpha', { enabled: true });
});

test('alerts: create, list, update, delete', async () => {
  const bad = await api('POST', '/alerts', { name: 'x', filters: { workArrangement: 'moon' } });
  assert.equal(bad.status, 422);
  const a = await api('POST', '/alerts', { name: 'Remote Flutter', filters: { q: 'flutter', workArrangement: 'remote' }, notify: { email: 'me@example.com' } });
  assert.equal(a.status, 201);
  assert.equal((await api('GET', '/alerts')).body.items.length, 1);
  const u = await api('PUT', `/alerts/${a.body.alert.id}`, { name: 'Remote Flutter 2', enabled: false, filters: { q: 'flutter' } });
  assert.equal(u.body.alert.enabled, false);
  assert.equal((await api('DELETE', `/alerts/${a.body.alert.id}`)).status, 200);
  assert.equal((await api('DELETE', `/alerts/${a.body.alert.id}`)).status, 404);
});

test('matching: an on-demand, local comparison of a CV with a job — nothing runs during scans', async () => {
  const created = await api('POST', '/searches', { ...SEARCH, name: 'for matching' });
  const run = await api('POST', `/searches/${created.body.search.id}/scan`);
  await waitFor(async () => (await api('GET', `/scans/${run.body.run.id}`)).body.run.status === 'completed');
  const id = (await api('GET', '/jobs?limit=1')).body.items[0].id;
  const m = await api('POST', `/jobs/${id}/match`, { cvText: 'Mobile engineer, 5 years of experience building Flutter and Dart apps with Firebase.' });
  assert.equal(m.status, 200);
  assert.equal(m.body.match.provider, 'keyword');
  assert.ok(m.body.match.score > 50);
  assert.ok(m.body.match.matchingSkills.includes('Flutter'));
  assert.equal((await api('POST', `/jobs/${id}/match`, {})).status, 422);
});

test('unknown routes and malformed JSON get proper status codes', async () => {
  assert.equal((await api('GET', '/nothing-here')).status, 404);
  const res = await fetch(`${base}/api/jobs/searches`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{oops' });
  assert.ok([400, 422].includes(res.status));
});

test('the API rate limit answers 429 with Retry-After', async () => {
  const limited = createJobsModule({ db: new FakeFirestore(), env: {}, log: silentLogger, registryOptions: { classes: [AlphaClass] }, routerOptions: { limiter: rateLimit({ max: 3, name: 'test' }) } });
  const app = express();
  app.use('/api/jobs', limited.router);
  const srv = await new Promise((r) => {
    const s = app.listen(0, '127.0.0.1', () => r(s));
  });
  try {
    const url = `http://127.0.0.1:${srv.address().port}/api/jobs/geo/countries`;
    const statuses = [];
    let last;
    for (let i = 0; i < 5; i++) {
      last = await fetch(url);
      statuses.push(last.status);
    }
    assert.deepEqual(statuses, [200, 200, 200, 429, 429]);
    assert.ok(Number(last.headers.get('retry-after')) > 0);
    assert.equal((await last.json()).code, 'RATE_LIMITED');
  } finally {
    await new Promise((r) => srv.close(r));
  }
});

test('with JOBS_REQUIRE_AUTH, calls need a verified account and only admins may change data', async () => {
  const verify = (req, res, next) => {
    const token = req.headers.authorization;
    if (!token) return res.status(401).json({ error: 'Missing bearer token', code: 'UNAUTHENTICATED' });
    req.uid = token.replace('Bearer ', '');
    return next();
  };
  const secured = createJobsModule({
    db: new FakeFirestore(), env: {}, log: silentLogger, registryOptions: { classes: [AlphaClass] },
    routerOptions: { auth: jobsAuth({ required: true, verify, roleOf: async (uid) => (uid === 'boss' ? 'admin' : 'salesman') }) },
  });
  const app = express();
  app.use(express.json());
  app.use('/api/jobs', secured.router);
  const srv = await new Promise((r) => {
    const s = app.listen(0, '127.0.0.1', () => r(s));
  });
  const b = `http://127.0.0.1:${srv.address().port}/api/jobs`;
  const call = (method, path, token, body) => fetch(`${b}${path}`, { method, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  try {
    assert.equal((await call('GET', '/geo/countries')).status, 401);
    assert.equal((await call('GET', '/geo/countries', 'sam')).status, 200);
    assert.equal((await call('POST', '/searches', 'sam', SEARCH)).status, 403, 'a salesman can read but not change');
    assert.equal((await call('POST', '/searches', 'boss', SEARCH)).status, 201);
  } finally {
    await new Promise((r) => srv.close(r));
  }
});
