/**
 * The scan engine: turns a saved search into a queue of combinations and works
 * through it in the background, independent of any browser session.
 *
 *   start() ─► run doc + queue (job_search_queue) ─► N workers ─► sources ─► jobStore
 *
 * Guarantees
 *  - A task is claimed by transaction, so it runs once (see queueStore).
 *  - One source failing never fails a combination: every source of a
 *    combination runs independently; the combination fails only when every
 *    source it tried failed. A source that keeps failing, runs out of quota,
 *    is refused (auth) or shows a bot wall is switched off for the rest of the
 *    run — the others carry on.
 *  - Pause stops claiming (in-flight tasks finish); resume continues; stop
 *    releases what was claimed and ends the run.
 *  - Progress is persisted (run doc + queue), so a restart can resume: tasks
 *    that were mid-flight are released and re-run — their jobs de-duplicate.
 *  - The same posting found twice (or by two sources) is one job (jobStore).
 */

import os from 'node:os';
import crypto from 'node:crypto';
import { Mutex } from '../../../lib/asyncMutex.js';
import { iterateCombinations, countCombinations, describeCombination } from './combinations.js';
import { isFatalForSource, SourceError, describeError, conflict, notFound, invalid } from '../utils/errors.js';
import { silentLogger } from '../utils/logger.js';
import { annualApprox } from '../utils/extract.js';
import { serialize } from './firestoreUtil.js';

const DEFAULTS = {
  flushMs: 1500,
  heartbeatMs: 5000,
  staleMs: 90_000, // a "running" run with no heartbeat for this long was interrupted
  comboAttempts: 2,
  comboRetryDelayMs: 4000,
  breakerThreshold: 5, // consecutive failures before a source is switched off for the run
  pausePollMs: 250,
  enqueueChunk: 2000,
  maxRecentErrors: 15,
  maxNewJobIds: 2000,
};

const TERMINAL = new Set(['completed', 'stopped', 'failed']);

/** Drops postings that clearly contradict the search's filters. Unknown values pass. */
export function applyFilters(jobs, filters = {}, now = new Date()) {
  const f = filters || {};
  const since = f.postedWithinDays ? now.getTime() - f.postedWithinDays * 86_400_000 : null;
  return jobs.filter((j) => {
    if (f.employmentType && j.employmentType && j.employmentType !== f.employmentType) return false;
    if (f.workArrangement && j.workArrangement && j.workArrangement !== f.workArrangement) return false;
    if (f.experienceLevel && j.experienceLevel && j.experienceLevel !== f.experienceLevel) return false;
    if (since && j.postedAt && j.postedAt.getTime() < since) return false;
    if (f.salaryMin != null && j.salaryMax != null) {
      if (f.salaryCurrency && j.salaryCurrency && j.salaryCurrency !== f.salaryCurrency) return true; // can't compare across currencies
      const annual = annualApprox(j.salaryMax, j.salaryPeriod);
      if (annual != null && annual < f.salaryMin) return false;
    }
    return true;
  });
}

function emptySourceStats() {
  return { state: 'ready', usable: true, requests: 0, combinations: 0, found: 0, new: 0, updated: 0, duplicate: 0, errors: 0, consecutiveFailures: 0, lastError: null, warnings: 0 };
}

export function createScanEngine({
  searchStore,
  runStore,
  queueStore,
  jobStore,
  companyStore,
  alertStore,
  sourceStore,
  registry,
  catalog,
  log = silentLogger,
  now = () => new Date(),
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  instanceId = `${os.hostname()}-${process.pid}-${crypto.randomBytes(3).toString('hex')}`,
  options = {},
} = {}) {
  const cfg = { ...DEFAULTS, ...options };
  /** @type {Map<string, any>} */
  const active = new Map();

  // ------------------------------------------------------------- snapshots
  function progressOf(ctx) {
    const c = ctx.counters;
    const finished = c.done + c.failed + c.skipped;
    return {
      id: ctx.id,
      searchId: ctx.searchId,
      searchName: ctx.searchName,
      trigger: ctx.trigger,
      status: ctx.status,
      totals: { combinations: c.total, completed: c.done, failed: c.failed, skipped: c.skipped, pending: Math.max(0, c.total - finished), running: ctx.inFlight },
      percent: c.total ? Math.min(100, Math.round((finished / c.total) * 1000) / 10) : 0,
      jobs: { found: c.found, new: c.new, updated: c.updated, duplicate: c.duplicate, suppressed: c.suppressed, filteredOut: c.filteredOut },
      sources: Object.fromEntries(Object.entries(ctx.sources).map(([id, s]) => [id, { ...s }])),
      current: [...ctx.current.values()],
      recentErrors: ctx.errors.slice(0, cfg.maxRecentErrors),
      errorSummary: ctx.errorSummary,
      enqueuing: ctx.enqueuing,
      startedAt: ctx.startedAt,
      finishedAt: ctx.finishedAt,
      heartbeatAt: now(),
    };
  }

  function runPatch(ctx) {
    const p = progressOf(ctx);
    return {
      status: p.status,
      totals: p.totals,
      percent: p.percent,
      jobs: p.jobs,
      sources: p.sources,
      current: p.current,
      recentErrors: p.recentErrors,
      errorSummary: p.errorSummary,
      enqueued: !ctx.enqueuing,
      finishedAt: ctx.finishedAt,
      heartbeatAt: ctx.heartbeatOverride || p.heartbeatAt,
      owner: instanceId,
    };
  }

  async function flush(ctx) {
    ctx.dirty = false;
    try {
      await runStore.patch(ctx.id, runPatch(ctx));
    } catch (err) {
      ctx.dirty = true;
      log.warn('could not save run progress', { runId: ctx.id, error: err });
    }
  }

  function touch(ctx) {
    ctx.dirty = true;
    if (ctx.flushTimer) return;
    ctx.flushTimer = setTimeout(() => {
      ctx.flushTimer = null;
      if (ctx.dirty) flush(ctx);
    }, cfg.flushMs);
    ctx.flushTimer.unref?.();
  }

  // --------------------------------------------------------------- sources
  function noteError(ctx, sourceId, err, task) {
    const d = describeError(err);
    ctx.errors.unshift({ at: now(), source: sourceId, kind: d.kind, status: d.status, message: d.message, combination: task ? describeCombination(task) : null });
    ctx.errors.length = Math.min(ctx.errors.length, 50);
    const bySource = (ctx.errorSummary[sourceId] ||= {});
    bySource[d.kind] = (bySource[d.kind] || 0) + 1;
  }

  function switchOff(ctx, sourceId, state, reason) {
    const s = ctx.sources[sourceId];
    if (!s.usable) return;
    s.usable = false;
    s.state = state;
    log.warn('source switched off for this run', { runId: ctx.id, source: sourceId, state, reason });
  }

  const OFF_STATE = { quota: 'quota_exhausted', auth: 'auth_failed', blocked: 'blocked', disallowed: 'disallowed', not_configured: 'not_configured' };

  async function runSource(ctx, sourceId, query, task) {
    const s = ctx.sources[sourceId];
    if (!s.usable) return { id: sourceId, ok: true, skipped: true, jobs: [] };
    try {
      const r = await ctx.adapters.get(sourceId).search(query, { maxPages: ctx.limits.maxPagesPerSource, maxResults: ctx.limits.maxResultsPerCombination });
      s.requests += r.pages;
      s.combinations += 1;
      s.found += r.jobs.length;
      s.consecutiveFailures = 0;
      for (const w of r.warnings || []) {
        s.warnings += 1;
        noteError(ctx, sourceId, new SourceError(w.kind === 'error' ? 'http_error' : w.kind, `${w.board}: ${w.message}`), task);
      }
      return { id: sourceId, ok: true, jobs: r.jobs };
    } catch (err) {
      s.errors += 1;
      s.consecutiveFailures += 1;
      s.lastError = describeError(err);
      noteError(ctx, sourceId, err, task);
      if (isFatalForSource(err)) switchOff(ctx, sourceId, OFF_STATE[err.kind] || 'failing', err.message);
      else if (s.consecutiveFailures >= cfg.breakerThreshold) switchOff(ctx, sourceId, 'failing', `${s.consecutiveFailures} consecutive failures`);
      return { id: sourceId, ok: false, error: err, jobs: [] };
    }
  }

  // ------------------------------------------------------------- one task
  async function processTask(ctx, task, slot) {
    const query = {
      country: { code: task.countryCode, name: task.country },
      state: task.state ?? null,
      city: task.city ?? null,
      remoteOnly: Boolean(task.remoteOnly),
      title: task.title,
      keywords: ctx.keywords,
      filters: ctx.filters,
    };
    ctx.current.set(slot, { country: task.country, state: task.state, city: task.city, remote: query.remoteOnly, title: task.title });
    ctx.inFlight += 1;
    touch(ctx);
    try {
      const applicable = ctx.sourceIds.filter((id) => ctx.sources[id].usable && ctx.adapters.get(id).supports(query));
      if (!applicable.length) {
        // Nothing can answer this combination (or every source that could was switched off).
        await queueStore.complete(task.id, { status: 'skipped', result: { reason: ctx.sourceIds.some((id) => !ctx.sources[id].usable) ? 'sources_unavailable' : 'no_source_supports_it' } });
        ctx.counters.skipped += 1;
        return;
      }

      let results = [];
      for (let attempt = 1; attempt <= cfg.comboAttempts; attempt++) {
        results = await Promise.all(applicable.map((id) => runSource(ctx, id, query, task)));
        const tried = results.filter((r) => !r.skipped);
        const allFailed = tried.length > 0 && tried.every((r) => !r.ok);
        const retryable = allFailed && tried.some((r) => r.error?.retryable);
        if (!retryable || attempt === cfg.comboAttempts || ctx.state === 'stopping') break;
        await sleep(cfg.comboRetryDelayMs * attempt);
      }

      const tried = results.filter((r) => !r.skipped);
      const allFailed = tried.length > 0 && tried.every((r) => !r.ok);

      // Ingest everything the combination found in one go so cross-source duplicates collapse.
      const found = results.flatMap((r) => r.jobs.map((job) => ({ job, source: r.id })));
      const kept = applyFilters(found.map((f) => f.job), ctx.filters, now());
      const keptSet = new Set(kept);
      const entries = found.filter((f) => keptSet.has(f.job));
      ctx.counters.filteredOut += found.length - entries.length;

      let outcomes = { new: 0, updated: 0, duplicate: 0, suppressed: 0 };
      if (entries.length) {
        const ingest = await jobStore.upsertMany(entries.map((e) => e.job), { runId: ctx.id, searchId: ctx.searchId });
        entries.forEach((e, i) => {
          const o = ingest.outcomes[i];
          if (o && ctx.sources[e.source][o] !== undefined) ctx.sources[e.source][o] += 1;
          if (o === 'new' && ingest.ids[i] && ctx.newJobIds.length < cfg.maxNewJobIds) ctx.newJobIds.push(ingest.ids[i]);
        });
        outcomes = { new: ingest.new, updated: ingest.updated, duplicate: ingest.duplicate, suppressed: ingest.suppressed };
        await companyStore?.recordSightings(entries.map((e) => e.job)).catch((err) => log.warn('company update failed', { error: err }));
      }
      const c = ctx.counters;
      c.found += entries.length;
      c.new += outcomes.new;
      c.updated += outcomes.updated;
      c.duplicate += outcomes.duplicate;
      c.suppressed += outcomes.suppressed;

      const summary = { found: entries.length, ...outcomes, sources: Object.fromEntries(results.map((r) => [r.id, r.skipped ? { status: 'off' } : r.ok ? { status: 'ok', found: r.jobs.length } : { status: 'error', error: describeError(r.error) }])) };
      if (allFailed) {
        await queueStore.complete(task.id, { status: 'failed', result: summary, error: describeError(tried[0].error) });
        c.failed += 1;
      } else {
        await queueStore.complete(task.id, { status: 'done', result: summary });
        c.done += 1;
      }
    } catch (err) {
      // Not a source problem (storage, a bug): the combination failed, the run goes on.
      log.error('combination failed', { runId: ctx.id, task: task.id, error: err });
      noteError(ctx, 'engine', err, task);
      await queueStore.complete(task.id, { status: 'failed', error: describeError(err) }).catch(() => {});
      ctx.counters.failed += 1;
    } finally {
      ctx.inFlight -= 1;
      ctx.current.delete(slot);
      touch(ctx);
    }
  }

  // --------------------------------------------------------------- workers
  async function nextTask(ctx) {
    return ctx.claimLock.runExclusive(async () => {
      if (ctx.buffer.length) return ctx.buffer.shift();
      if (ctx.state !== 'running') return null;
      const batch = await queueStore.claim(ctx.id, instanceId, Math.max(1, ctx.limits.concurrency));
      ctx.buffer.push(...batch);
      return ctx.buffer.shift() || null;
    });
  }

  async function worker(ctx, slot) {
    for (;;) {
      if (ctx.state === 'stopping') return;
      if (ctx.state === 'paused') {
        await sleep(cfg.pausePollMs);
        continue;
      }
      const task = await nextTask(ctx);
      if (!task) {
        if (ctx.enqueuing && ctx.state === 'running') {
          await sleep(200);
          continue;
        }
        return;
      }
      if (ctx.state === 'stopping') {
        ctx.buffer.unshift(task);
        return;
      }
      await processTask(ctx, task, slot);
    }
  }

  // -------------------------------------------------------------- finishing
  async function finish(ctx) {
    clearTimeout(ctx.flushTimer);
    clearInterval(ctx.heartbeat);
    ctx.flushTimer = null;
    // Anything claimed but not started goes back to the queue.
    if (ctx.buffer.length) {
      await queueStore.release(ctx.buffer.map((t) => t.id)).catch(() => {});
      ctx.buffer = [];
    }
    const c = ctx.counters;
    if (ctx.shuttingDown) {
      // The process is going away, not the scan: leave it resumable. An old heartbeat
      // makes the next boot (or the next scheduler tick) pick it up immediately.
      ctx.status = 'interrupted';
      ctx.state = 'done';
      ctx.current.clear();
      ctx.heartbeatOverride = new Date(0);
      await flush(ctx);
      await registry.flush().catch(() => {});
      active.delete(ctx.id);
      log.info('scan interrupted by shutdown', { runId: ctx.id, totals: progressOf(ctx).totals });
      return;
    }
    if (ctx.state === 'stopping') ctx.status = 'stopped';
    else if (c.total > 0 && c.done === 0 && c.failed > 0) ctx.status = 'failed';
    else ctx.status = 'completed';
    ctx.state = 'done';
    ctx.finishedAt = now();
    ctx.current.clear();

    await flush(ctx);
    await registry.flush().catch(() => {});

    // Remember each source's outcome, and tell the alerts about new jobs.
    for (const [id, s] of Object.entries(ctx.sources)) {
      if (s.combinations + s.errors === 0) continue;
      await sourceStore?.recordOutcome(id, { ok: s.errors === 0 || s.found > 0, error: s.lastError?.message ?? null }).catch(() => {});
    }
    if (alertStore && ctx.newJobIds.length) {
      try {
        const snaps = await Promise.all(ctx.newJobIds.map((id) => jobStore.get(id)));
        await alertStore.evaluate(snaps.filter(Boolean).map((s) => ({ id: s.id, ...s.data() })));
      } catch (err) {
        log.warn('alert evaluation failed', { runId: ctx.id, error: err });
      }
    }
    await searchStore.markRun(ctx.searchId, { runId: ctx.id, status: ctx.status }).catch(() => {});
    active.delete(ctx.id);
    log.info('scan finished', { runId: ctx.id, status: ctx.status, totals: progressOf(ctx).totals, jobs: progressOf(ctx).jobs });
  }

  async function launch(ctx, { reenqueue }) {
    ctx.heartbeat = setInterval(() => flush(ctx), cfg.heartbeatMs);
    ctx.heartbeat.unref?.();
    active.set(ctx.id, ctx);
    try {
      if (reenqueue) {
        ctx.enqueuing = true;
        ctx.status = 'queued';
        await flush(ctx);
        const iterator = iterateCombinations(ctx.searchForCombos, catalog);
        let chunk = [];
        let seq = 0;
        const send = async () => {
          if (!chunk.length) return;
          await queueStore.enqueue(ctx.id, ctx.searchId, chunk, { startSeq: seq });
          seq += chunk.length;
          chunk = [];
          // Workers may start as soon as the first chunk is in the queue.
          if (ctx.status === 'queued') {
            ctx.status = 'running';
            ctx.workers = startWorkers(ctx);
          }
        };
        for (const combo of iterator) {
          chunk.push(combo);
          if (chunk.length >= cfg.enqueueChunk) await send();
        }
        await send();
        ctx.enqueuing = false;
      }
      if (!ctx.workers) {
        ctx.status = ctx.state === 'paused' ? 'paused' : 'running';
        ctx.workers = startWorkers(ctx);
      }
      await flush(ctx);
      await Promise.all(ctx.workers);
    } catch (err) {
      log.error('scan crashed', { runId: ctx.id, error: err });
      noteError(ctx, 'engine', err, null);
      ctx.enqueuing = false;
      ctx.state = ctx.state === 'stopping' ? 'stopping' : 'running';
      ctx.counters.failed = Math.max(ctx.counters.failed, 1);
    }
    await finish(ctx);
  }

  function startWorkers(ctx) {
    return Array.from({ length: ctx.limits.concurrency }, (_, i) => worker(ctx, i + 1));
  }

  // --------------------------------------------------------------- building
  function buildContext({ id, searchId, searchName, trigger, config, adapters, sourceStates, counters, jobs, startedAt, sources }) {
    const sourceStats = {};
    for (const sid of config.sources) sourceStats[sid] = { ...emptySourceStats(), ...(sources?.[sid] || {}) , ...(sourceStates[sid] || {}) };
    return {
      id, searchId, searchName, trigger,
      state: 'running', // running | paused | stopping | done
      status: 'queued',
      limits: config.limits,
      keywords: config.keywords || [],
      filters: config.filters || {},
      searchForCombos: { titles: config.titles, countries: config.countries },
      sourceIds: [...adapters.keys()],
      adapters,
      sources: sourceStats,
      counters: { total: 0, done: 0, failed: 0, skipped: 0, found: 0, new: 0, updated: 0, duplicate: 0, suppressed: 0, filteredOut: 0, ...(counters || {}), ...(jobs || {}) },
      current: new Map(),
      buffer: [],
      claimLock: new Mutex(),
      inFlight: 0,
      errors: [],
      errorSummary: {},
      newJobIds: [],
      enqueuing: false,
      dirty: false,
      flushTimer: null,
      heartbeat: null,
      workers: null,
      startedAt,
      finishedAt: null,
    };
  }

  async function prepareSources(requested) {
    await registry.load();
    const ids = registry.selected(requested);
    const adapters = new Map();
    const sourceStates = {};
    for (const id of ids) {
      const adapter = registry.adapter(id);
      adapters.set(id, adapter);
      if (!adapter.isConfigured()) sourceStates[id] = { state: 'not_configured', usable: false, lastError: { kind: 'not_configured', message: adapter.configurationHint() } };
    }
    return { ids, adapters, sourceStates };
  }

  // ------------------------------------------------------------------- API
  async function start(searchId, { trigger = 'manual' } = {}) {
    const search = await searchStore.getData(searchId);
    if (search.enabled === false) throw conflict('This search is disabled', 'SEARCH_DISABLED');

    const existing = [...active.values()].find((c) => c.searchId === searchId) || (await runStore.findActiveForSearch(searchId));
    if (existing) throw conflict(`This search already has an active scan (${existing.id})`, 'SCAN_ALREADY_ACTIVE');

    const count = countCombinations(search, catalog);
    if (!count.combinations) throw invalid('This search expands to no combinations: check the countries and job titles');
    if (count.combinations > search.limits.maxCombinations) {
      throw invalid(`This search expands to ${count.combinations.toLocaleString('en-US')} combinations, above its limit of ${search.limits.maxCombinations.toLocaleString('en-US')}. Narrow the selection or raise the limit.`, count);
    }

    const { ids, adapters, sourceStates } = await prepareSources(search.sources);
    if (!ids.length) throw invalid('No source is enabled for this search');
    if (!ids.some((id) => !sourceStates[id])) {
      const hints = ids.map((id) => `${id}: ${sourceStates[id].lastError.message}`).join(' ');
      throw invalid(`None of the selected sources is configured. ${hints}`);
    }

    const id = runStore.newId();
    const startedAt = now();
    const config = { titles: search.titles, keywords: search.keywords, filters: search.filters, limits: search.limits, countries: search.countries, sources: ids };
    const ctx = buildContext({ id, searchId, searchName: search.name, trigger, config, adapters, sourceStates, startedAt });
    ctx.counters.total = count.combinations;
    await runStore.create({
      id, searchId, searchName: search.name, trigger, status: 'queued', config, owner: instanceId, enqueued: false,
      totals: { combinations: count.combinations, completed: 0, failed: 0, skipped: 0, pending: count.combinations, running: 0 },
      jobs: { found: 0, new: 0, updated: 0, duplicate: 0, suppressed: 0, filteredOut: 0 },
      sources: ctx.sources, startedAt, finishedAt: null, heartbeatAt: startedAt,
    });
    log.info('scan started', { runId: id, searchId, trigger, combinations: count.combinations, sources: ids });
    launch(ctx, { reenqueue: true }).catch((err) => log.error('scan launch failed', { runId: id, error: err })); // background: the HTTP request returns now
    return serialize(progressOf(ctx));
  }

  /** Rebuilds a run that is no longer in memory (after a restart, or a pause that survived one). */
  async function rehydrate(run, { paused = false } = {}) {
    const config = run.config;
    const { adapters, sourceStates } = await prepareSources(config.sources);
    const released = await queueStore.releaseStale(run.id, { force: true });
    const counts = await queueStore.counts(run.id);
    const ctx = buildContext({
      id: run.id, searchId: run.searchId, searchName: run.searchName, trigger: 'resume', config, adapters, sourceStates,
      counters: { total: run.totals?.combinations ?? counts.total, done: counts.done, failed: counts.failed, skipped: counts.skipped },
      jobs: { found: run.jobs?.found ?? 0, new: run.jobs?.new ?? 0, updated: run.jobs?.updated ?? 0, duplicate: run.jobs?.duplicate ?? 0, suppressed: run.jobs?.suppressed ?? 0, filteredOut: run.jobs?.filteredOut ?? 0 },
      sources: run.sources, startedAt: run.startedAt?.toDate?.() ?? run.startedAt,
    });
    // Switched-off states from before the restart are re-evaluated: quota resets, keys get fixed.
    for (const s of Object.values(ctx.sources)) if (s.state !== 'not_configured') Object.assign(s, { usable: true, state: 'ready', consecutiveFailures: 0 });
    for (const [sid, st] of Object.entries(sourceStates)) Object.assign(ctx.sources[sid], st);
    ctx.state = paused ? 'paused' : 'running';
    log.info('scan resumed', { runId: run.id, releasedTasks: released, counts });
    launch(ctx, { reenqueue: run.enqueued !== true }).catch((err) => log.error('scan launch failed', { runId: run.id, error: err }));
    return ctx;
  }

  const activeOrThrow = (runId) => {
    const ctx = active.get(runId);
    if (!ctx) throw conflict('This scan is not running on this server', 'SCAN_NOT_ACTIVE');
    return ctx;
  };

  async function pause(runId) {
    const ctx = activeOrThrow(runId);
    if (ctx.state !== 'running') throw conflict(`Cannot pause a scan that is ${ctx.state}`, 'BAD_STATE');
    ctx.state = 'paused';
    ctx.status = 'paused';
    await flush(ctx);
    return serialize(progressOf(ctx));
  }

  async function resume(runId) {
    const ctx = active.get(runId);
    if (ctx) {
      if (ctx.state !== 'paused') throw conflict(`Cannot resume a scan that is ${ctx.state}`, 'BAD_STATE');
      ctx.state = 'running';
      ctx.status = 'running';
      await flush(ctx);
      return serialize(progressOf(ctx));
    }
    const run = await runStore.get(runId);
    if (!run) throw notFound('Scan run not found');
    if (!['paused', 'interrupted'].includes(run.status)) throw conflict(`Cannot resume a scan that is ${run.status}`, 'BAD_STATE');
    if ([...active.values()].some((c) => c.searchId === run.searchId)) throw conflict('This search already has an active scan', 'SCAN_ALREADY_ACTIVE');
    const ctx2 = await rehydrate(run);
    ctx2.status = 'running';
    return serialize(progressOf(ctx2));
  }

  async function stop(runId) {
    const ctx = active.get(runId);
    if (ctx) {
      if (ctx.state === 'done') throw conflict('This scan has already finished', 'BAD_STATE');
      ctx.state = 'stopping';
      ctx.status = 'stopping';
      await flush(ctx);
      return serialize(progressOf(ctx));
    }
    // Not in memory (server restarted while it was paused/interrupted): end it directly.
    const run = await runStore.get(runId);
    if (!run) throw notFound('Scan run not found');
    if (TERMINAL.has(run.status)) throw conflict(`This scan has already ${run.status === 'stopped' ? 'been stopped' : 'finished'}`, 'BAD_STATE');
    await queueStore.releaseStale(runId, { force: true });
    await runStore.patch(runId, { status: 'stopped', finishedAt: now(), current: [] });
    await searchStore.markRun(run.searchId, { runId, status: 'stopped' }).catch(() => {});
    return serialize({ ...(await runStore.get(runId)), id: runId });
  }

  /** Live numbers for an active run; the stored document otherwise. */
  async function progress(runId) {
    const ctx = active.get(runId);
    if (ctx) return serialize(progressOf(ctx));
    return runStore.getApi(runId);
  }

  /**
   * At boot: runs this server left "running" are interrupted — mark them and,
   * if [autoResume], pick them up again where the queue says they were.
   */
  async function recoverInterrupted({ autoResume = true } = {}) {
    const stamp = now().getTime();
    const recovered = [];
    for (const run of await runStore.listActive()) {
      if (active.has(run.id)) continue;
      const beat = run.heartbeatAt?.toMillis?.() ?? new Date(run.heartbeatAt || 0).getTime();
      if (run.status === 'paused') continue; // stays paused until someone resumes it
      if (stamp - beat < cfg.staleMs) continue; // another live instance owns it
      if (run.status === 'stopping') {
        await stop(run.id).catch(() => {});
        continue;
      }
      await runStore.patch(run.id, { status: 'interrupted' });
      if (autoResume) {
        await rehydrate({ ...run, status: 'interrupted' });
        recovered.push(run.id);
      }
      log.warn('interrupted scan found', { runId: run.id, resumed: autoResume });
    }
    return recovered;
  }

  /** Waits for every active run to finish — graceful shutdown and tests. */
  async function idle() {
    while (active.size) {
      await Promise.all([...active.values()].map((c) => c.workers && Promise.all(c.workers).catch(() => {})));
      await sleep(10);
    }
  }

  /**
   * For a process that is about to exit: stop claiming, give in-flight tasks a
   * moment to finish, and leave every active scan `interrupted` (resumable).
   */
  async function shutdown({ timeoutMs = 4000 } = {}) {
    const runs = [...active.values()];
    for (const ctx of runs) {
      ctx.shuttingDown = true;
      ctx.state = 'stopping';
      ctx.status = 'stopping';
    }
    const settled = Promise.all(runs.map((c) => (c.workers ? Promise.all(c.workers).catch(() => {}) : null)));
    await Promise.race([settled, new Promise((r) => setTimeout(r, timeoutMs).unref?.())]);
    // Anything still not finished is cut off by the exit: record that now.
    for (const ctx of runs) {
      if (!active.has(ctx.id)) continue;
      ctx.heartbeatOverride = new Date(0);
      ctx.status = 'interrupted';
      await flush(ctx);
    }
  }

  return { start, pause, resume, stop, progress, recoverInterrupted, idle, shutdown, activeRunIds: () => [...active.keys()], instanceId, _active: active };
}
