import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { GreenhouseAdapter } from './greenhouse.js';
import { LeverAdapter } from './lever.js';
import { AshbyAdapter } from './ashby.js';
import { WorkableAdapter } from './workable.js';
import { AdzunaAdapter } from './adzuna.js';
import { JoobleAdapter } from './jooble.js';
import { RemotiveAdapter } from './remotive.js';
import { JobSourceAdapter } from './baseAdapter.js';
import { createSourceGate } from '../utils/sourceGate.js';
import { SourceError } from '../utils/errors.js';
import { TtlCache } from '../utils/ttlCache.js';
import { buildJob } from './buildJob.js';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures');
const fixture = (name) => JSON.parse(fs.readFileSync(path.join(dir, `${name}.json`), 'utf8'));

/** A scripted HTTP client: routes by substring of the URL; records every call. */
function fakeHttp(routes) {
  const calls = [];
  const respond = async (method, url, payload, opts = {}) => {
    calls.push({ method, url, payload, query: opts.query });
    for (const [needle, value] of routes) {
      if (url.includes(needle)) {
        const v = typeof value === 'function' ? value({ url, payload, query: opts.query }) : value;
        if (v instanceof Error) throw v;
        return structuredClone(v);
      }
    }
    throw new SourceError('not_found', `HTTP 404 ${url}`, { status: 404, retryable: false });
  };
  return {
    calls,
    getJson: (url, opts) => respond('GET', url, null, opts),
    postJson: (url, payload, opts) => respond('POST', url, payload, opts),
    getText: (url, opts) => respond('GET', url, null, opts),
  };
}

const gate = (id = 't') => createSourceGate({ id, perMinute: 600000, perDay: Infinity, maxConcurrent: 8, sleep: async () => {}, jitter: 0 });
const make = (Cls, http, { settings = {}, env = {} } = {}) => new Cls({ http, gate: gate(Cls.meta.id), settings, env, cache: new TtlCache() });

const Q = (over = {}) => ({ country: { code: 'US', name: 'United States' }, state: null, city: null, remoteOnly: false, title: 'Product Manager', keywords: [], filters: {}, ...over });

// ------------------------------------------------------------------ Greenhouse

test('greenhouse: reads a public board and normalizes a posting from the real payload shape', async () => {
  const http = fakeHttp([['/boards/airbnb/jobs', fixture('greenhouse')]]);
  const a = make(GreenhouseAdapter, http, { settings: { boards: ['airbnb'] } });
  const r = await a.search(Q({ state: 'California', city: 'San Francisco', title: 'Product Manager' }));
  assert.equal(r.jobs.length, 1);
  const j = r.jobs[0];
  assert.equal(j.title, 'Product Manager, Trips');
  assert.equal(j.companyName, 'Airbnb');
  assert.equal(j.source, 'greenhouse');
  assert.equal(j.city, 'San Francisco');
  assert.equal(j.state, 'California');
  assert.equal(j.countryCode, 'US');
  assert.ok(j.postedAt instanceof Date, 'first_published is the posted date');
  assert.ok(j.sourceUpdatedAt instanceof Date);
  assert.match(j.sourceUrl, /^https:\/\//);
  assert.equal(j.applyUrlDirect, true);
  assert.ok(j.description.length > 200 && !/<\/?[a-z]+/i.test(j.description), 'HTML-escaped content becomes plain text');
  assert.equal(j.salaryMin, null, 'no pay was published');
  assert.equal(j.companyWebsite, null);
  assert.deepEqual(j.sourceRef, { board: 'airbnb' });
});

test('greenhouse: matching is by title and place — other cities, other titles and remote-only are excluded', async () => {
  const http = fakeHttp([['/boards/airbnb/jobs', fixture('greenhouse')]]);
  const a = make(GreenhouseAdapter, http, { settings: { boards: ['airbnb'] } });
  assert.equal((await a.search(Q({ title: 'Product Manager', state: 'California', city: 'Los Angeles' }))).jobs.length, 0, 'wrong city');
  assert.equal((await a.search(Q({ title: 'Product Manager', state: 'California', city: 'San Francisco' }))).jobs.length, 1);
  assert.equal((await a.search(Q({ title: 'Accountant', state: 'California', city: 'San Francisco' }))).jobs.length, 0, 'wrong title');
  assert.equal((await a.search(Q({ title: 'Product Manager', remoteOnly: true }))).jobs.length, 0, 'not a remote posting');
});

test('greenhouse: a country-level search finds postings anywhere in that country', async () => {
  const http = fakeHttp([['/boards/airbnb/jobs', fixture('greenhouse')]]);
  const a = make(GreenhouseAdapter, http, { settings: { boards: ['airbnb'] } });
  const us = await a.search(Q({ title: 'Product Manager' }));
  assert.deepEqual(us.jobs.map((j) => j.title), ['Product Manager, Trips']);
  const sg = await a.search(Q({ country: { code: 'SG', name: 'Singapore' }, title: 'Program Manager' }));
  assert.equal(sg.jobs.length, 0, 'Singapore is not a configured dataset, so no false country match');
});

test('board adapters fetch each board once however many combinations ask', async () => {
  const http = fakeHttp([['/boards/airbnb/jobs', fixture('greenhouse')]]);
  const a = make(GreenhouseAdapter, http, { settings: { boards: ['airbnb'] } });
  await Promise.all([a.search(Q()), a.search(Q({ title: 'Design' })), a.search(Q({ city: 'San Francisco', state: 'California' }))]);
  await a.search(Q({ title: 'Manager' }));
  assert.equal(http.calls.length, 1);
});

test('one failing board is a warning; all boards failing is a failure', async () => {
  const http = fakeHttp([['/boards/airbnb/jobs', fixture('greenhouse')], ['/boards/gone/jobs', new SourceError('not_found', 'HTTP 404', { status: 404 })]]);
  const mixed = make(GreenhouseAdapter, http, { settings: { boards: ['gone', 'airbnb'] } });
  const r = await mixed.search(Q({ title: 'Product Manager' }));
  assert.equal(r.jobs.length, 1);
  assert.equal(r.warnings.length, 1);
  assert.equal(r.warnings[0].board, 'gone');

  const allBad = make(GreenhouseAdapter, fakeHttp([['/boards/', new SourceError('http_error', 'HTTP 500', { status: 500 })]]), { settings: { boards: ['a', 'b'] } });
  await assert.rejects(() => allBad.search(Q()), (e) => e instanceof SourceError && e.source === 'greenhouse');
});

test('board adapters with no boards are "not configured" and say what to add', async () => {
  const a = make(GreenhouseAdapter, fakeHttp([]));
  assert.equal(a.isConfigured(), false);
  await assert.rejects(() => a.search(Q()), (e) => e.kind === 'not_configured' && /board token/.test(e.message));
  assert.equal(a.describe().configured, false);
});

test('greenhouse: a 404 on the posting is the definitive "gone"; an outage is not', async () => {
  const a = make(GreenhouseAdapter, fakeHttp([['/jobs/111', new SourceError('not_found', 'HTTP 404', { status: 404 })], ['/jobs/222', new SourceError('timeout', 'timed out')]]));
  assert.deepEqual(await a.getJobDetails({ sourceJobId: '111', sourceRef: { board: 'airbnb' } }), { found: false, job: null });
  await assert.rejects(() => a.getJobDetails({ sourceJobId: '222', sourceRef: { board: 'airbnb' } }), (e) => e.kind === 'timeout');
  assert.deepEqual(await a.getJobDetails({ sourceJobId: '1' }), { found: null, job: null }, 'without a board reference it cannot tell');
});

// ------------------------------------------------------------------------ Lever

test('lever: normalizes the real payload — country, hybrid arrangement, commitment, requirement lists', async () => {
  const http = fakeHttp([['/v0/postings/palantir', fixture('lever')]]);
  const a = make(LeverAdapter, http, { settings: { boards: [{ id: 'palantir', name: 'Palantir' }] } });
  const r = await a.search(Q({ title: 'Finance Operator', state: 'New York', city: 'New York City' }));
  assert.ok(r.jobs.length >= 1, JSON.stringify(r.jobs.map((j) => j.locationText)));
  const j = r.jobs.find((x) => x.title === 'Finance Operator');
  assert.equal(j.companyName, 'Palantir');
  assert.equal(j.countryCode, 'US');
  assert.equal(j.workArrangement, 'hybrid');
  assert.equal(j.employmentType, 'full_time');
  assert.ok(j.postedAt instanceof Date);
  assert.match(j.applyUrl, /\/apply$|jobs\.lever\.co/);
  assert.ok(j.description.length > 100);
});

test('lever: EU accounts use the EU host', async () => {
  const http = fakeHttp([['api.eu.lever.co', []], ['api.lever.co', []]]);
  await make(LeverAdapter, http, { settings: { boards: [{ id: 'acme', region: 'eu' }] } }).search(Q());
  assert.match(http.calls[0].url, /^https:\/\/api\.eu\.lever\.co\/v0\/postings\/acme/);
});

// ------------------------------------------------------------------------ Ashby

test('ashby: remote postings, published pay and employment type from the real payload', async () => {
  const http = fakeHttp([['/job-board/ashby', fixture('ashby')]]);
  const a = make(AshbyAdapter, http, { settings: { boards: [{ id: 'ashby', name: 'Ashby' }] } });
  const us = await a.search(Q({ remoteOnly: true, title: 'Solutions Engineering Manager' }));
  assert.equal(us.jobs.length, 1);
  const j = us.jobs[0];
  assert.equal(j.workArrangement, 'remote');
  assert.equal(j.employmentType, 'full_time');
  assert.deepEqual([j.salaryMin, j.salaryMax, j.salaryCurrency, j.salaryPeriod], [235000, 302019, 'USD', 'year']);
  assert.ok(j.postedAt instanceof Date);

  // "Remote - European Union" can't be placed in one country: not offered to a US search...
  assert.equal((await a.search(Q({ remoteOnly: true, title: 'Recruiting Operations Consultant' }))).jobs.length, 0);
  // ...but a worldwide-remote search sees every remote posting.
  const ww = await a.search(Q({ country: { code: 'WW', name: 'Worldwide / Remote' }, remoteOnly: true, title: 'Recruiting Operations Consultant' }));
  assert.equal(ww.jobs.length, 1);
  assert.deepEqual([ww.jobs[0].salaryCurrency], ['EUR']);
});

// --------------------------------------------------------------------- Workable

test('workable: maps the documented widget payload', async () => {
  const payload = {
    name: 'Huspy',
    description: null,
    jobs: [
      { title: 'Flutter Developer', shortcode: 'ABC123', employment_type: 'Full-time', telecommuting: false, department: 'Engineering', url: 'https://apply.workable.com/huspy/j/ABC123', shortlink: 'https://apply.workable.com/j/ABC123', application_url: 'https://apply.workable.com/huspy/j/ABC123/apply', published_on: '2026-10-30', created_at: '2026-10-29', country: 'United Arab Emirates', city: 'Dubai', state: 'Dubai', education: 'Bachelor Degree', experience: 'Mid-Senior level', description: '<p>Build the app.</p><h3>Requirements</h3><ul><li>3+ years of Flutter experience</li></ul>', locations: [{ country: 'United Arab Emirates', countryCode: 'AE', city: 'Dubai', region: 'Dubai', hidden: false }] },
      { title: 'Sales Lead', shortcode: 'DEF456', telecommuting: true, url: 'https://apply.workable.com/huspy/j/DEF456', country: 'Qatar', city: 'Doha', description: '<p>Sell.</p>' },
    ],
  };
  const a = make(WorkableAdapter, fakeHttp([['/widget/accounts/huspy', payload]]), { settings: { boards: ['huspy'] } });
  const r = await a.search(Q({ country: { code: 'AE', name: 'United Arab Emirates' }, state: 'Dubai', city: 'Dubai', title: 'Flutter Developer' }));
  assert.equal(r.jobs.length, 1);
  const j = r.jobs[0];
  assert.equal(j.companyName, 'Huspy');
  assert.equal(j.countryCode, 'AE');
  assert.equal(j.employmentType, 'full_time');
  assert.equal(j.educationText, 'Bachelor Degree');
  assert.equal(j.experienceYearsMin, 3);
  assert.ok(j.requiredSkills.includes('Flutter'));
  const remote = await a.search(Q({ country: { code: 'QA', name: 'Qatar' }, state: 'Doha', city: 'Doha', title: 'Sales Lead' }));
  assert.equal(remote.jobs[0]?.workArrangement, 'remote');
});

// ----------------------------------------------------------------------- Adzuna

const ADZUNA_PAGE = (n, count) => ({
  count,
  results: Array.from({ length: n }, (_, i) => ({
    id: `${1000 + i}`,
    title: 'Senior <strong>Flutter</strong> Developer',
    description: 'Looking for a <strong>Flutter</strong> developer with Dart experience to join our mobile team…',
    created: '2026-11-04T08:00:00Z',
    redirect_url: `https://www.adzuna.com/land/ad/${1000 + i}?se=abc`,
    company: { display_name: 'Acme Inc' },
    location: { display_name: 'Los Angeles, Los Angeles County', area: ['US', 'California', 'Los Angeles County', 'Los Angeles'] },
    salary_min: i === 0 ? 120000 : 90000,
    salary_max: i === 0 ? 150000 : 110000,
    salary_is_predicted: i === 0 ? '0' : '1',
    contract_type: 'permanent',
    contract_time: 'full_time',
    category: { label: 'IT Jobs', tag: 'it-jobs' },
  })),
});

test('adzuna: builds the documented request and normalizes results (predicted pay is not stored)', async () => {
  const http = fakeHttp([['/jobs/us/search/1', ADZUNA_PAGE(2, 2)]]);
  const a = make(AdzunaAdapter, http, { env: { ADZUNA_APP_ID: 'id1', ADZUNA_APP_KEY: 'key1' } });
  const r = await a.search(Q({ state: 'California', city: 'Los Angeles', title: 'Flutter Developer', keywords: ['dart'], filters: { postedWithinDays: 7, employmentType: 'full_time', salaryMin: 50000 } }));
  const call = http.calls[0];
  assert.equal(call.query.what, 'Flutter Developer dart');
  assert.equal(call.query.where, 'Los Angeles, California');
  assert.equal(call.query.max_days_old, 7);
  assert.equal(call.query.full_time, 1);
  assert.equal(call.query.salary_min, 50000);
  assert.equal(call.query.results_per_page, 50);

  assert.equal(r.jobs.length, 2);
  const [real, predicted] = r.jobs;
  assert.equal(real.title, 'Senior Flutter Developer', 'highlight markup removed');
  assert.deepEqual([real.salaryMin, real.salaryMax, real.salaryCurrency, real.salaryPeriod], [120000, 150000, 'USD', 'year']);
  assert.deepEqual([predicted.salaryMin, predicted.salaryMax], [null, null], 'a prediction is not a published salary');
  assert.equal(real.state, 'California');
  assert.equal(real.city, 'Los Angeles');
  assert.equal(real.countryCode, 'US');
  assert.equal(real.descriptionTruncatedBySource, true);
  assert.equal(real.applyUrl, null, "Adzuna's redirect is not the employer's page");
  assert.match(real.sourceUrl, /adzuna\.com/);
});

test('adzuna: follows pagination up to the page limit and reports truncation', async () => {
  const http = fakeHttp([['/search/1', ADZUNA_PAGE(50, 400)], ['/search/2', () => ({ count: 400, results: ADZUNA_PAGE(50, 400).results.map((x, i) => ({ ...x, id: `p2-${i}` })) })], ['/search/3', ADZUNA_PAGE(50, 400)]]);
  const a = make(AdzunaAdapter, http, { env: { ADZUNA_APP_ID: 'id1', ADZUNA_APP_KEY: 'key1' } });
  const r = await a.search(Q({ title: 'Developer' }), { maxPages: 2, maxResults: 500 });
  assert.equal(http.calls.length, 2);
  assert.equal(r.jobs.length, 100);
  assert.equal(r.truncated, true);
  const capped = await make(AdzunaAdapter, fakeHttp([['/search/1', ADZUNA_PAGE(50, 400)]]), { env: { ADZUNA_APP_ID: 'x', ADZUNA_APP_KEY: 'y' } }).search(Q(), { maxPages: 3, maxResults: 20 });
  assert.equal(capped.jobs.length, 20);
});

test('adzuna: unsupported countries are skipped, missing keys are reported, keys never leak into the description', async () => {
  const a = make(AdzunaAdapter, fakeHttp([]), { env: { ADZUNA_APP_ID: 'id1', ADZUNA_APP_KEY: 'secret-key' } });
  assert.equal(a.supports(Q({ country: { code: 'QA', name: 'Qatar' } })), false);
  assert.equal(a.supports(Q({ country: { code: 'DE', name: 'Germany' } })), true);
  const keyless = make(AdzunaAdapter, fakeHttp([]));
  assert.equal(keyless.isConfigured(), false);
  await assert.rejects(() => keyless.search(Q()), (e) => e.kind === 'not_configured' && /ADZUNA_APP_ID/.test(e.message));
  assert.ok(!JSON.stringify(a.describe()).includes('secret-key'));
});

// ----------------------------------------------------------------------- Jooble

test('jooble: posts the documented body and normalizes results including pay text', async () => {
  const payload = {
    totalCount: 2,
    jobs: [
      { id: 7001, title: '<b>Flutter</b> Developer', location: 'Doha', snippet: 'Build <b>Flutter</b> apps for retail clients…', salary: 'QAR 18,000 - 25,000 monthly', source: 'bayt.com', type: 'Full-time', link: 'https://jooble.org/desc/7001', company: 'Qatar Digital', updated: '2026-11-05T10:00:00.0000000' },
      { id: 7002, title: 'Mobile Engineer', location: 'Al Rayyan', snippet: 'Join us.', salary: '', type: '', link: 'https://jooble.org/desc/7002', company: 'Gulf Apps', updated: '2026-11-01T10:00:00' },
    ],
  };
  const http = fakeHttp([['jooble.org/api/test-key', payload]]);
  const a = make(JoobleAdapter, http, { env: { JOOBLE_API_KEY: 'test-key' } });
  const r = await a.search(Q({ country: { code: 'QA', name: 'Qatar' }, state: 'Doha', city: 'Doha', title: 'Flutter Developer', keywords: ['dart'] }));
  assert.equal(http.calls[0].method, 'POST');
  assert.equal(http.calls[0].payload.keywords, 'Flutter Developer dart');
  assert.equal(http.calls[0].payload.location, 'Doha, Qatar');
  assert.equal(r.jobs.length, 2);
  const j = r.jobs[0];
  assert.equal(j.title, 'Flutter Developer');
  assert.deepEqual([j.salaryMin, j.salaryMax, j.salaryCurrency, j.salaryPeriod], [18000, 25000, 'QAR', 'month']);
  assert.equal(j.countryCode, 'QA', 'the search was scoped to Qatar');
  assert.equal(j.city, 'Doha');
  assert.equal(j.employmentType, 'full_time');
  assert.equal(r.jobs[1].salaryMin, null, 'empty pay stays null');
  assert.equal(r.jobs[1].employmentType, null);
});

test('jooble: a country-level remote search asks for "remote" and sets no country on the results', async () => {
  const http = fakeHttp([['jooble.org/api/', { totalCount: 1, jobs: [{ id: 1, title: 'Flutter Dev', location: 'Remote', snippet: 'x', link: 'https://jooble.org/desc/1', company: 'Co', updated: '2026-11-01' }] }]]);
  const a = make(JoobleAdapter, http, { env: { JOOBLE_API_KEY: 'k' } });
  const r = await a.search(Q({ country: { code: 'WW', name: 'Worldwide / Remote' }, remoteOnly: true, title: 'Flutter Dev' }));
  assert.equal(http.calls[0].payload.keywords, 'Flutter Dev remote');
  assert.equal(http.calls[0].payload.location, '');
  assert.equal(r.jobs[0].countryCode, null);
  assert.equal(r.jobs[0].workArrangement, 'remote');
});

// --------------------------------------------------------------------- Remotive

test('remotive: one request for the whole feed, credited and linked back to Remotive', async () => {
  const http = fakeHttp([['remotive.com/api/remote-jobs', fixture('remotive')]]);
  const a = make(RemotiveAdapter, http);
  const r1 = await a.search(Q({ remoteOnly: true, title: 'Patient Care Advocate' }));
  const r2 = await a.search(Q({ country: { code: 'WW', name: 'Worldwide / Remote' }, remoteOnly: true, title: 'Freelance Writer' }));
  assert.equal(http.calls.length, 1, 'cached for hours: Remotive asks for at most a few calls a day');
  assert.equal(r1.jobs.length, 1);
  assert.match(r1.jobs[0].sourceUrl, /^https:\/\/remotive\.com\//);
  assert.equal(r1.jobs[0].applyUrl, null);
  assert.equal(r1.jobs[0].workArrangement, 'remote');
  assert.equal(r1.jobs[0].salaryMin, 25000);
  assert.equal(r2.jobs[0].employmentType, 'freelance');
  assert.equal(r2.jobs[0].salaryPeriod, 'hour');
  assert.equal(RemotiveAdapter.meta.defaultLimits.perDay, 4);
});

test('remotive only answers remote searches; a city search is not its job', () => {
  const a = make(RemotiveAdapter, fakeHttp([]));
  assert.equal(a.supports(Q({ city: 'Houston', state: 'Texas' })), false);
  assert.equal(a.supports(Q({ remoteOnly: true })), true);
  assert.equal(a.supports(Q({ country: { code: 'WW', name: 'Worldwide / Remote' }, remoteOnly: true })), true);
});

// ------------------------------------------------------------------ base template

class PagedFake extends JobSourceAdapter {
  static meta = { ...JobSourceAdapter.meta, id: 'paged', defaultMaxPages: 5 };
  constructor(deps, script) {
    super(deps);
    this.script = script;
  }
  async fetchPage(_q, page) {
    return this.script(page);
  }
  normalize(raw) {
    return raw === 'bad' ? null : buildJob({ source: 'paged', sourceJobId: raw, title: `T${raw}`, companyName: 'Co', sourceUrl: `https://x.test/${raw}` });
  }
}

test('base search: later-page failures keep earlier results; a first-page failure propagates; bad records are skipped', async () => {
  const deps = { http: {}, gate: gate('paged') };
  const partial = new PagedFake(deps, async (page) => {
    if (page === 2) throw new SourceError('timeout', 'slow');
    return { items: ['a', 'bad', 'b'], hasMore: true };
  });
  const r = await partial.search(Q());
  assert.equal(r.jobs.length, 2);
  assert.equal(r.skipped, 1);
  assert.equal(r.truncated, true);

  const dead = new PagedFake(deps, async () => {
    throw new SourceError('http_error', 'HTTP 500', { status: 500 });
  });
  await assert.rejects(() => dead.search(Q()), (e) => e.status === 500 && e.source === 'paged');

  const quota = new PagedFake(deps, async (page) => {
    if (page === 2) throw new SourceError('quota', 'budget');
    return { items: ['a'], hasMore: true };
  });
  await assert.rejects(() => quota.search(Q()), (e) => e.kind === 'quota');
});

test('buildJob never invents: missing facts stay null, and unusable records are dropped', () => {
  const j = buildJob({ source: 's', sourceJobId: '1', title: 'Barista', companyName: 'Cafe', sourceUrl: 'https://x.test/1' });
  for (const field of ['companyWebsite', 'salaryMin', 'salaryMax', 'salaryCurrency', 'salaryPeriod', 'employmentType', 'experienceLevel', 'experienceYearsMin', 'educationText', 'postedAt', 'deadlineAt', 'workArrangement', 'recruiter', 'country', 'countryCode', 'state', 'city', 'responsibilities', 'description']) {
    assert.equal(j[field], null, `${field} should be null`);
  }
  assert.deepEqual(j.requiredSkills, []);
  assert.equal(buildJob({ source: 's', sourceJobId: '1', title: '', companyName: 'x' }), null);
  assert.equal(buildJob({ source: 's', title: 'x', companyName: 'x' }), null);
});

test('buildJob extracts what the text states: pay, experience, education, skills, responsibilities', () => {
  const j = buildJob({
    source: 's',
    sourceJobId: '9',
    title: 'Senior Flutter Developer (m/f/d)',
    companyName: 'Acme',
    locationText: 'Munich, Bavaria, Germany',
    salaryText: '€70.000 - €85.000 pro Jahr',
    employmentTypeText: 'Full-time',
    descriptionHtml: '<h3>Responsibilities</h3><ul><li>Build apps</li><li>Review code</li></ul><h3>Requirements</h3><ul><li>5+ years of experience with Flutter and Dart</li><li>Bachelor degree in Computer Science</li></ul><h3>Nice to have</h3><ul><li>Kotlin</li></ul><p>This is a hybrid role. Full-time.</p>',
  });
  assert.deepEqual([j.countryCode, j.state, j.city], ['DE', 'Bavaria', 'Munich']);
  assert.deepEqual([j.salaryMin, j.salaryMax, j.salaryCurrency, j.salaryPeriod], [70000, 85000, 'EUR', 'year']);
  assert.equal(j.experienceLevel, 'senior');
  assert.equal(j.experienceYearsMin, 5);
  assert.match(j.educationText, /Bachelor/);
  assert.deepEqual(j.requiredSkills, ['Flutter', 'Dart']);
  assert.deepEqual(j.preferredSkills, ['Kotlin']);
  assert.deepEqual(j.responsibilities, ['Build apps', 'Review code']);
  assert.equal(j.workArrangement, 'hybrid');
  assert.equal(j.employmentType, 'full_time');
});
