import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeHarness, FakeAdapter, sampleJob, LA_SF_SEARCH, waitFor } from '../testing/engineHarness.js';
import { applyFilters } from './scanEngine.js';
import { SourceError } from '../utils/errors.js';
import { COLLECTIONS } from '../models/constants.js';

/** One distinct job per (city, title) so every combination stores something. */
const jobFor = (q, source = 'alpha') =>
  sampleJob({
    source,
    sourceJobId: `${q.city}-${q.title}`,
    sourceUrl: `https://${source}.test/${encodeURIComponent(q.city)}/${encodeURIComponent(q.title)}`,
    title: q.title,
    locationText: `${q.city}, CA`,
  });

const okSource = (id = 'alpha') => new FakeAdapter(id, async (q) => [jobFor(q, id)]);

async function startAndFinish(h, searchConfig = LA_SF_SEARCH) {
  const search = await h.searchStore.create(searchConfig);
  const run = await h.engine.start(search.id);
  await h.engine.idle();
  return { search, run, final: await h.runStore.getApi(run.id) };
}

test('a scan expands the search, runs every combination and stores the jobs', async () => {
  const h = makeHarness({ adapters: [okSource()] });
  const { search, final } = await startAndFinish(h);

  assert.equal(final.status, 'completed');
  assert.equal(final.totals.combinations, 4); // 2 cities x 2 titles
  assert.equal(final.totals.completed, 4);
  assert.equal(final.totals.failed, 0);
  assert.equal(final.jobs.new, 4);
  assert.equal(final.sources.alpha.requests, 4);
  assert.equal((await h.queueStore.counts(final.id)).done, 4);
  assert.equal(h.db.dump(COLLECTIONS.jobs).length, 4);
  assert.equal(h.db.dump(COLLECTIONS.companies).length, 1);
  const stored = await h.searchStore.getApi(search.id);
  assert.equal(stored.lastRunId, final.id);
  assert.equal(stored.lastRunStatus, 'completed');
  assert.ok(final.finishedAt);
});

test('every combination reaches the source with its own country, state, city and title', async () => {
  const src = okSource();
  const h = makeHarness({ adapters: [src] });
  await startAndFinish(h);
  const seen = src.calls.map((q) => `${q.state}|${q.city}|${q.title}`).sort();
  assert.deepEqual(seen, [
    'California|Los Angeles|Flutter Developer',
    'California|Los Angeles|Senior Flutter Developer',
    'California|San Francisco|Flutter Developer',
    'California|San Francisco|Senior Flutter Developer',
  ]);
  assert.ok(src.calls.every((q) => q.country.code === 'US' && q.remoteOnly === false));
});

test('running the same search again creates no duplicate jobs', async () => {
  const h = makeHarness({ adapters: [okSource()] });
  const search = await h.searchStore.create(LA_SF_SEARCH);
  await h.engine.start(search.id);
  await h.engine.idle();
  const second = await h.engine.start(search.id);
  await h.engine.idle();
  const final = await h.runStore.getApi(second.id);
  assert.equal(h.db.dump(COLLECTIONS.jobs).length, 4);
  assert.equal(final.jobs.new, 0);
  assert.equal(final.jobs.duplicate, 4);
});

test('one failing source does not stop the others, and is switched off after repeated failures', async () => {
  const bad = new FakeAdapter('beta', async () => {
    throw new SourceError('http_error', 'HTTP 500', { status: 500, retryable: false });
  });
  const h = makeHarness({ adapters: [okSource(), bad], options: { breakerThreshold: 2 } });
  const { final } = await startAndFinish(h);

  assert.equal(final.status, 'completed', 'the run succeeds because alpha does');
  assert.equal(final.totals.completed, 4);
  assert.equal(final.totals.failed, 0);
  assert.equal(final.jobs.new, 4);
  assert.equal(final.sources.beta.state, 'failing');
  assert.equal(final.sources.beta.usable, false);
  assert.ok(final.sources.beta.errors >= 2);
  assert.ok(bad.calls.length < 4, 'once switched off, the failing source is not called for the remaining combinations');
  assert.equal(final.sources.alpha.state, 'ready');
  assert.ok(final.errorSummary.beta.http_error >= 2);
});

test('a source refused with an auth error is switched off at once; others carry on', async () => {
  const denied = new FakeAdapter('beta', async () => {
    throw new SourceError('auth', 'HTTP 403 (access denied)', { status: 403, retryable: false });
  });
  const h = makeHarness({ adapters: [okSource(), denied] });
  const { final } = await startAndFinish(h);
  assert.equal(final.sources.beta.state, 'auth_failed');
  assert.equal(final.totals.completed, 4);
  assert.ok(denied.calls.length <= 2, 'at most the combinations already in flight');
});

test('an exhausted daily quota switches the source off without failing the combinations', async () => {
  const quota = new FakeAdapter('beta', async () => {
    throw new SourceError('quota', 'Daily request budget is used up', { retryable: false });
  });
  const h = makeHarness({ adapters: [okSource(), quota] });
  const { final } = await startAndFinish(h);
  assert.equal(final.sources.beta.state, 'quota_exhausted');
  assert.equal(final.status, 'completed');
  assert.equal(final.totals.failed, 0);
});

test('when every source fails a combination, it is retried and then recorded as failed', async () => {
  const flaky = new FakeAdapter('alpha', async () => {
    throw new SourceError('timeout', 'Request timed out', { retryable: true });
  });
  const h = makeHarness({ adapters: [flaky], options: { comboAttempts: 2, breakerThreshold: 100 } });
  const { final } = await startAndFinish(h);
  assert.equal(final.totals.failed, 4);
  assert.equal(final.status, 'failed');
  assert.equal(flaky.calls.length, 8, 'two attempts per combination');
  const failed = await h.queueStore.failedSample(final.id);
  assert.equal(failed.length, 4);
  assert.equal(failed[0].error.kind, 'timeout');
});

test('a transient failure that clears on retry still completes the combination', async () => {
  let n = 0;
  const flaky = new FakeAdapter('alpha', async (q) => {
    n += 1;
    if (n === 1) throw new SourceError('timeout', 'Request timed out', { retryable: true });
    return [jobFor(q)];
  });
  const h = makeHarness({ adapters: [flaky], options: { breakerThreshold: 100 } });
  const { final } = await startAndFinish(h);
  assert.equal(final.totals.failed, 0);
  assert.equal(final.totals.completed, 4);
});

test('sources that are not configured are reported and skipped; with none usable the scan will not start', async () => {
  const keyless = new FakeAdapter('beta', async () => [], { configured: false, hint: 'Set BETA_KEY' });
  const h = makeHarness({ adapters: [okSource(), keyless] });
  const { final } = await startAndFinish(h);
  assert.equal(final.sources.beta.state, 'not_configured');
  assert.equal(final.sources.beta.requests, 0);
  assert.equal(keyless.calls.length, 0);

  const h2 = makeHarness({ adapters: [keyless] });
  const search = await h2.searchStore.create(LA_SF_SEARCH);
  await assert.rejects(() => h2.engine.start(search.id), (e) => e.status === 422 && /BETA_KEY/.test(e.message));
});

test('a combination no source supports is skipped, not failed', async () => {
  const onlyTexas = new FakeAdapter('alpha', async (q) => [jobFor(q)], { supports: (q) => q.state === 'Texas' });
  const h = makeHarness({ adapters: [onlyTexas] });
  const { final } = await startAndFinish(h);
  assert.equal(final.totals.skipped, 4);
  assert.equal(final.totals.failed, 0);
  assert.equal(final.status, 'completed');
});

test('the same posting returned by two sources is stored once', async () => {
  const a = new FakeAdapter('alpha', async (q) => [jobFor(q, 'alpha')]);
  const b = new FakeAdapter('beta', async (q) => [{ ...jobFor(q, 'beta'), sourceJobId: `b-${q.city}-${q.title}` }]);
  const h = makeHarness({ adapters: [a, b] });
  const { final } = await startAndFinish(h);
  assert.equal(h.db.dump(COLLECTIONS.jobs).length, 4);
  assert.equal(final.jobs.found, 8);
  assert.equal(final.jobs.new, 4);
  assert.equal(final.jobs.updated + final.jobs.duplicate, 4);
  const [[, doc]] = h.db.dump(COLLECTIONS.jobs);
  assert.deepEqual([...doc.sourceNames].sort(), ['alpha', 'beta']);
});

test('a search that expands past its limit is refused with the real count', async () => {
  const h = makeHarness({ adapters: [okSource()] });
  const search = await h.searchStore.create({ ...LA_SF_SEARCH, limits: { ...LA_SF_SEARCH.limits, maxCombinations: 3 } });
  await assert.rejects(() => h.engine.start(search.id), (e) => e.status === 422 && /4 combinations/.test(e.message));
});

test('starting a search that already has an active scan is a conflict', async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  const slow = new FakeAdapter('alpha', async (q) => {
    await gate;
    return [jobFor(q)];
  });
  const h = makeHarness({ adapters: [slow] });
  const search = await h.searchStore.create(LA_SF_SEARCH);
  await h.engine.start(search.id);
  await assert.rejects(() => h.engine.start(search.id), (e) => e.status === 409 && e.code === 'SCAN_ALREADY_ACTIVE');
  release();
  await h.engine.idle();
});

test('pause stops claiming new combinations; resume finishes the run', async () => {
  let started = 0;
  const src = new FakeAdapter('alpha', async (q) => {
    started += 1;
    await new Promise((r) => setTimeout(r, 30));
    return [jobFor(q)];
  });
  const cfg = { ...LA_SF_SEARCH, limits: { ...LA_SF_SEARCH.limits, concurrency: 1 }, titles: ['A', 'B', 'C', 'D', 'E'] }; // 10 combinations
  const h = makeHarness({ adapters: [src] });
  const search = await h.searchStore.create(cfg);
  const run = await h.engine.start(search.id);

  await waitFor(() => started >= 2);
  const paused = await h.engine.pause(run.id);
  assert.equal(paused.status, 'paused');
  await waitFor(async () => (await h.engine.progress(run.id)).totals.running === 0);
  const frozen = started;
  await new Promise((r) => setTimeout(r, 80));
  assert.equal(started, frozen, 'nothing new starts while paused');
  assert.ok((await h.engine.progress(run.id)).totals.pending > 0);

  await assert.rejects(() => h.engine.pause(run.id), (e) => e.status === 409);
  const resumed = await h.engine.resume(run.id);
  assert.equal(resumed.status, 'running');
  await h.engine.idle();
  const final = await h.runStore.getApi(run.id);
  assert.equal(final.status, 'completed');
  assert.equal(final.totals.completed, 10);
});

test('stop ends the run, releases what was claimed, and leaves the rest untouched', async () => {
  let started = 0;
  const src = new FakeAdapter('alpha', async (q) => {
    started += 1;
    await new Promise((r) => setTimeout(r, 25));
    return [jobFor(q)];
  });
  const cfg = { ...LA_SF_SEARCH, limits: { ...LA_SF_SEARCH.limits, concurrency: 2 }, titles: ['A', 'B', 'C', 'D', 'E', 'F'] }; // 12 combinations
  const h = makeHarness({ adapters: [src] });
  const search = await h.searchStore.create(cfg);
  const run = await h.engine.start(search.id);
  await waitFor(() => started >= 2);
  await h.engine.stop(run.id);
  await h.engine.idle();

  const final = await h.runStore.getApi(run.id);
  assert.equal(final.status, 'stopped');
  const counts = await h.queueStore.counts(run.id);
  assert.equal(counts.running, 0, 'no task is left claimed');
  assert.ok(counts.pending > 0 && counts.done > 0);
  assert.equal(counts.done + counts.pending, 12);
  await assert.rejects(() => h.engine.stop(run.id), (e) => e.status === 409);
});

test('an interrupted run is resumed from its queue after a restart', async () => {
  // Stage a crash: a run that was running, with one finished task, one claimed by a dead worker and the rest pending.
  const src = okSource();
  const h = makeHarness({ adapters: [src] });
  const search = await h.searchStore.create(LA_SF_SEARCH);
  const first = await h.engine.start(search.id);
  await h.engine.idle();
  const runId = first.id;

  // Rewind everything to "mid-flight": two tasks back to pending/running, run marked running with a stale heartbeat.
  const tasks = h.db.dump(COLLECTIONS.queue).map(([id]) => id);
  const [t0, t1, t2] = tasks;
  h.db.docs.get(`${COLLECTIONS.queue}/${t0}`).status = 'pending';
  const running = h.db.docs.get(`${COLLECTIONS.queue}/${t1}`);
  running.status = 'running';
  running.leaseUntil = new Date(Date.now() - 1000);
  h.db.docs.get(`${COLLECTIONS.queue}/${t2}`).status = 'pending';
  const run = h.db.docs.get(`${COLLECTIONS.scanRuns}/${runId}`);
  Object.assign(run, { status: 'running', heartbeatAt: new Date(Date.now() - 10 * 60_000), finishedAt: null, enqueued: true });
  h.db.docs.get(`${COLLECTIONS.searches}/${search.id}`).lastRunStatus = null;
  src.calls.length = 0;

  const recovered = await h.engine.recoverInterrupted();
  assert.deepEqual(recovered, [runId]);
  await h.engine.idle();

  const final = await h.runStore.getApi(runId);
  assert.equal(final.status, 'completed');
  assert.equal(src.calls.length, 3, 'only the three unfinished combinations ran again');
  assert.equal((await h.queueStore.counts(runId)).done, 4);
  assert.equal(h.db.dump(COLLECTIONS.jobs).length, 4, 'no duplicates from the replay');
});

test('a fresh heartbeat means another server owns the run: recovery leaves it alone', async () => {
  const h = makeHarness({ adapters: [okSource()] });
  const search = await h.searchStore.create(LA_SF_SEARCH);
  const first = await h.engine.start(search.id);
  await h.engine.idle();
  Object.assign(h.db.docs.get(`${COLLECTIONS.scanRuns}/${first.id}`), { status: 'running', heartbeatAt: new Date() });
  assert.deepEqual(await h.engine.recoverInterrupted(), []);
});

test('alerts are matched against the jobs a scan newly found', async () => {
  const h = makeHarness({ adapters: [okSource()] });
  await h.alertStore.create({ name: 'LA flutter', enabled: true, filters: { q: 'flutter', city: 'Los Angeles' }, notify: {} });
  await h.alertStore.create({ name: 'Texas', enabled: true, filters: { state: 'Texas' }, notify: {} });
  await startAndFinish(h);
  const alerts = h.db.dump(COLLECTIONS.alerts).map(([, a]) => a);
  const la = alerts.find((a) => a.name === 'LA flutter');
  const tx = alerts.find((a) => a.name === 'Texas');
  assert.equal(la.lastMatchCount, 2);
  assert.equal(tx.lastMatchCount, 0);
});

test('applyFilters drops clear contradictions but keeps jobs whose value is unknown', () => {
  const jobs = [
    { id: 1, employmentType: 'full_time', workArrangement: 'remote', experienceLevel: 'senior', postedAt: new Date('2026-11-06') },
    { id: 2, employmentType: 'contract', workArrangement: null, experienceLevel: null, postedAt: null },
    { id: 3, employmentType: 'part_time', workArrangement: 'onsite', experienceLevel: 'entry', postedAt: new Date('2026-01-01') },
    { id: 4, employmentType: null, workArrangement: null, experienceLevel: null, postedAt: null, salaryMax: 30000, salaryPeriod: 'year', salaryCurrency: 'USD' },
  ];
  const now = new Date('2026-11-07');
  assert.deepEqual(applyFilters(jobs, { employmentType: 'full_time' }, now).map((j) => j.id), [1, 4]);
  assert.deepEqual(applyFilters(jobs, { workArrangement: 'remote' }, now).map((j) => j.id), [1, 2, 4]);
  assert.deepEqual(applyFilters(jobs, { postedWithinDays: 30 }, now).map((j) => j.id), [1, 2, 4]);
  assert.deepEqual(applyFilters(jobs, { salaryMin: 50000, salaryCurrency: 'USD' }, now).map((j) => j.id), [1, 2, 3]);
  assert.deepEqual(applyFilters(jobs, {}, now).length, 4);
});

test('concurrent claims never hand the same task to two workers', async () => {
  const h = makeHarness({ adapters: [okSource()] });
  const combos = Array.from({ length: 20 }, (_, i) => ({ key: `k${i}`, countryCode: 'US', country: 'United States', state: 'Texas', city: `C${i}`, remoteOnly: false, title: 'X' }));
  await h.queueStore.enqueue('run-x', 's1', combos);
  const batches = await Promise.all(Array.from({ length: 5 }, (_, i) => h.queueStore.claim('run-x', `w${i}`, 6)));
  const ids = batches.flat().map((t) => t.id);
  assert.equal(new Set(ids).size, ids.length, 'no task claimed twice');
  assert.equal(ids.length, 20);
});

test('graceful shutdown leaves the scan interrupted, and the next process resumes it at once', async () => {
  let started = 0;
  const slow = new FakeAdapter('alpha', async (q) => {
    started += 1;
    await new Promise((r) => setTimeout(r, 25));
    return [jobFor(q)];
  });
  const cfg = { ...LA_SF_SEARCH, limits: { ...LA_SF_SEARCH.limits, concurrency: 1 }, titles: ['A', 'B', 'C', 'D', 'E', 'F'] }; // 12 combinations
  const h = makeHarness({ adapters: [slow] });
  const search = await h.searchStore.create(cfg);
  const run = await h.engine.start(search.id);
  await waitFor(() => started >= 2);

  await h.engine.shutdown({ timeoutMs: 2000 });
  const stored = await h.runStore.getApi(run.id);
  assert.equal(stored.status, 'interrupted');
  assert.equal(new Date(stored.heartbeatAt).getTime(), 0, 'stale on purpose: nobody else owns it');
  assert.deepEqual(h.engine.activeRunIds(), []);
  const mid = await h.queueStore.counts(run.id);
  assert.ok(mid.done >= 1 && mid.pending > 0);
  assert.equal(mid.running, 0, 'what was claimed but not started was handed back');

  // "Next boot": a fresh engine on the same database.
  const reborn = makeHarness({ adapters: [slow] });
  reborn.db.docs = h.db.docs;
  const resumed = await reborn.engine.recoverInterrupted();
  assert.deepEqual(resumed, [run.id]);
  await reborn.engine.idle();
  const final = await reborn.runStore.getApi(run.id);
  assert.equal(final.status, 'completed');
  assert.equal((await reborn.queueStore.counts(run.id)).done, 12);
  assert.equal(reborn.db.dump(COLLECTIONS.jobs).length, 12, 'every combination stored exactly once');
});
