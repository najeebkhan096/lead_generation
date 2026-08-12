/**
 * Concurrent multi-category search: a configurable worker pool where each
 * worker independently pulls the next category off a shared queue and runs
 * the exact same nationwide scrape (`scrapeCategoryNationwide`) that the
 * single-category and legacy sequential flows use — nothing about the
 * scraping logic itself changes here, only the orchestration around it.
 *
 * "Worker" here is a logical concurrency slot (an async loop), not an OS
 * thread — Playwright's own work is I/O-bound (waiting on page loads), and
 * each state scrape already runs in its own browser process/context, so
 * Node's single-threaded event loop interleaving concurrent workers gives
 * the same real-world parallelism as `worker_threads` would, without the
 * complexity of moving Playwright + progress messaging across threads.
 *
 * Only one multi-category job runs at a time, matching the rest of the
 * app's "one search at a time" model (mirrors `memoryStore.js`). The
 * control API (cancel/pause/status) always targets `currentJob`, the
 * latest job. Worker execution, however, is bound to the *specific* job
 * object it was spawned for (passed explicitly, never read back off
 * `currentJob`) — a worker can be mid-flight (e.g. still in its startup
 * stagger delay) when a caller starts the next job, and it must keep
 * mutating the job it actually belongs to, not whatever job happens to be
 * "current" by the time it wakes up.
 */

import { launchBrowser } from '../scraper/googleMapsScraper.js';
import { scrapeCategoryNationwide } from './leadService.js';
import { saveLeadsToFirebase } from './firebaseLeadStore.js';
import { setLastSearch } from '../utils/memoryStore.js';
import { countryMeta, regionsForCountry } from '../data/countries.js';
import { Mutex } from '../utils/asyncMutex.js';
import { leadsToXlsxBuffer } from './exportService.js';
import { uploadExcelArchive, buildArchiveFileName } from './excelArchiveStore.js';

const MIN_CONCURRENCY = 2;
const MAX_CONCURRENCY = 8;
const DEFAULT_CONCURRENCY = 4;
const ACTIVITY_LOG_LIMIT = 300;
const WORKER_STAGGER_MS = 1200;
const PAUSE_POLL_MS = 300;

/** @type {Job | null} */
let currentJob = null;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function clampConcurrency(value) {
  const n = Number(value) || DEFAULT_CONCURRENCY;
  return Math.min(MAX_CONCURRENCY, Math.max(MIN_CONCURRENCY, Math.round(n)));
}

function humanDuration(ms) {
  if (!Number.isFinite(ms) || ms < 0) return '0s';
  const totalSeconds = Math.round(ms / 1000);
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

/** Unique id for one (category, country) unit of work in the queue/records map. */
function workKey(category, country) {
  return `${category}::${country}`;
}

function newWorkItemRecord(category, country, label, statesTotal) {
  return {
    category,
    country,
    label,
    status: 'queued', // queued | starting | searching | scraping | saving | completed | failed | cancelled
    workerId: null,
    statesDone: 0,
    statesTotal,
    currentState: null,
    businessesProcessed: 0,
    // Businesses processed across states fully completed so far — the
    // baseline `businessesProcessed` is added to as the current state's
    // live listing count comes in (see 'scraper-message' below).
    completedBusinessesTotal: 0,
    leadsCollected: 0,
    startedAt: null,
    finishedAt: null,
    lastActivityAt: null,
    warnings: [],
    error: null,
    cancelled: false,
    paused: false,
  };
}

function logActivity(thisJob, message, level = 'info') {
  thisJob.activityLog.push({ timestamp: Date.now(), level, message });
  if (thisJob.activityLog.length > ACTIVITY_LOG_LIMIT) {
    thisJob.activityLog.splice(0, thisJob.activityLog.length - ACTIVITY_LOG_LIMIT);
  }
}

/** Scraper progress events -> this category's record. */
function applyCategoryProgress(thisJob, rec, evt) {
  rec.lastActivityAt = Date.now();
  switch (evt.type) {
    case 'state-start':
      rec.currentState = evt.state;
      rec.statesDone = evt.statesDone - 1; // this state isn't done yet
      rec.statesTotal = evt.statesTotal;
      rec.status = 'searching';
      break;
    case 'scraper-message': {
      rec.status = 'scraping';
      // "Opening listing X/Y" fires on every listing attempted — the only
      // reliable live signal for progress within the current state. Without
      // this, businessesProcessed only jumped once per state (on
      // 'businesses-scraped' below), sitting frozen for most of a scan.
      const openingMatch = evt.message.match(/^Opening listing (\d+)\/(\d+)/);
      if (openingMatch) {
        rec.businessesProcessed = rec.completedBusinessesTotal + parseInt(openingMatch[1], 10);
      }
      break;
    }
    case 'businesses-scraped':
      rec.completedBusinessesTotal = evt.total;
      rec.businessesProcessed = evt.total;
      break;
    case 'leads-found':
      rec.leadsCollected = evt.total;
      logActivity(
        thisJob,
        `"${rec.label}" +${evt.newLeads.length} lead${evt.newLeads.length === 1 ? '' : 's'} in ${rec.currentState} (${evt.total} total)`
      );
      break;
    case 'state-error':
      rec.warnings.push({ timestamp: Date.now(), message: evt.message });
      logActivity(thisJob, `"${rec.label}" — ${evt.message}`, 'warn');
      break;
    case 'state-done':
      rec.statesDone = evt.statesDone;
      logActivity(thisJob, `"${rec.label}" — ${evt.state} completed (${evt.statesDone}/${evt.statesTotal})`);
      break;
  }
}

async function waitWhilePausedFor(thisJob, rec) {
  while ((thisJob.paused || rec.paused) && !thisJob.cancelled && !rec.cancelled) {
    await sleep(PAUSE_POLL_MS);
  }
}

/** Default `saveLeadsFn` for `exportOnly` jobs — keeps leads in memory,
 * keyed by work item, instead of writing them to Firestore. Picked up by
 * `finishJob` once every category is done to build the Excel archive. */
function collectInMemory(thisJob) {
  return async (leads, ctx) => {
    const key = workKey(ctx.category, ctx.country);
    (thisJob.collectedLeads[key] ??= []).push(...leads);
    return { saved: leads.length };
  };
}

async function saveCategoryLeads(thisJob, rec, leads) {
  // Serializes the read-check-write sequence inside saveLeadsToFirebase
  // (and the shared `lastSearch` metadata it reads) so two workers'
  // Firebase writes can never interleave.
  return thisJob.firebaseMutex.runExclusive(async () => {
    setLastSearch({
      category: rec.category,
      location: countryMeta(rec.country).label,
      country: rec.country,
      nationwide: true,
    });
    return thisJob.saveLeadsFn(leads, { category: rec.category, country: rec.country, label: rec.label });
  });
}

async function runWorker(workerId, scrapeLocationFn, thisJob) {
  await sleep((workerId - 1) * WORKER_STAGGER_MS);

  while (true) {
    if (thisJob.cancelled) break;
    const key = thisJob.queue.shift();
    if (!key) break;

    const rec = thisJob.records[key];
    rec.workerId = workerId;
    rec.status = 'starting';
    rec.startedAt = Date.now();
    rec.lastActivityAt = Date.now();
    logActivity(thisJob, `Worker ${workerId} started "${rec.label}"`);

    try {
      const { leads, meta } = await scrapeCategoryNationwide(rec.category, {
        dateRange: thisJob.dateRange,
        maxResultsPerState: thisJob.maxResultsPerState,
        targetLeadCount: thisJob.targetLeadCount,
        analyze: thisJob.analyze,
        country: rec.country,
        browser: thisJob.browser,
        stopAtTarget: true,
        scrapeLocationFn,
        onProgress: (evt) => applyCategoryProgress(thisJob, rec, evt),
        shouldStop: () => thisJob.cancelled || rec.cancelled,
        waitWhilePaused: () => waitWhilePausedFor(thisJob, rec),
      });

      const cancelled = rec.cancelled || meta.stoppedReason === 'cancelled';

      if (leads.length) {
        rec.status = 'saving';
        logActivity(
          thisJob,
          `"${rec.label}" scraping ${cancelled ? 'stopped' : 'complete'} — saving ${leads.length} lead${leads.length === 1 ? '' : 's'}...`
        );
        try {
          await saveCategoryLeads(thisJob, rec, leads);
        } catch (saveErr) {
          rec.warnings.push({ timestamp: Date.now(), message: `Save failed: ${saveErr.message}` });
          logActivity(thisJob, `"${rec.label}" — Firebase save failed: ${saveErr.message}`, 'warn');
        }
      }

      rec.leadsCollected = leads.length;
      rec.finishedAt = Date.now();
      rec.status = cancelled ? 'cancelled' : 'completed';
      logActivity(
        thisJob,
        `"${rec.label}" ${cancelled ? 'cancelled' : 'completed'} in ${humanDuration(rec.finishedAt - rec.startedAt)} — ${leads.length} leads.`
      );
    } catch (err) {
      rec.status = 'failed';
      rec.error = err.message;
      rec.finishedAt = Date.now();
      logActivity(thisJob, `"${rec.label}" failed: ${err.message}`, 'error');
      // Swallow and continue — one work item's failure must not stop the rest.
    }
  }

  thisJob.activeWorkers -= 1;
  if (thisJob.activeWorkers === 0) await finishJob(thisJob);
}

async function buildAndUploadArchive(thisJob, totalLeads, totalBusinessesProcessed) {
  thisJob.archiveStatus = 'building';
  try {
    const sheets = Object.entries(thisJob.collectedLeads)
      .filter(([, leads]) => leads.length)
      .map(([key, leads]) => ({ name: thisJob.records[key].label, leads }));

    const buffer = await leadsToXlsxBuffer(sheets);
    const fileName = buildArchiveFileName({ categories: thisJob.categories, countries: thisJob.countries });
    const record = await uploadExcelArchive({
      buffer,
      fileName,
      categories: thisJob.categories,
      countries: thisJob.countries,
      totalLeads,
      totalBusinessesProcessed,
    });

    thisJob.archiveStatus = 'done';
    thisJob.archiveResult = record;
    logActivity(thisJob, `Excel archive uploaded: ${record.fileName} (${totalLeads} leads).`);
  } catch (err) {
    thisJob.archiveStatus = 'failed';
    thisJob.archiveError = err.message;
    logActivity(thisJob, `Excel archive upload failed: ${err.message}`, 'error');
  }
}

async function finishJob(thisJob) {
  if (thisJob.status === 'done') return;
  thisJob.status = 'done';
  thisJob.finishedAt = Date.now();
  try {
    await thisJob.browser?.close();
  } catch {
    // ignore
  }
  const totalLeads = Object.values(thisJob.records).reduce((sum, r) => sum + (r.leadsCollected || 0), 0);
  const totalBusinessesProcessed = Object.values(thisJob.records).reduce((sum, r) => sum + (r.businessesProcessed || 0), 0);
  const scope = thisJob.countries.length > 1
    ? `${thisJob.categories.length} categor${thisJob.categories.length === 1 ? 'y' : 'ies'} × ${thisJob.countries.length} countries`
    : `${thisJob.categories.length} categories`;
  logActivity(
    thisJob,
    `Multi-category search finished in ${humanDuration(thisJob.finishedAt - thisJob.startedAt)} — ${totalLeads} total leads across ${scope}.`
  );

  if (thisJob.exportOnly) {
    await buildAndUploadArchive(thisJob, totalLeads, totalBusinessesProcessed);
  }
}

function isRunningStatus(status) {
  return status === 'starting' || status === 'searching' || status === 'scraping' || status === 'saving';
}

/**
 * @param {object} opts
 * @param {string[]} opts.categories
 * @param {string[]} [opts.countries] - country codes to run every category
 *   against, e.g. ['US','UK','DE','CA'] for "search this category in all
 *   countries". Each (category, country) pair becomes its own queued work
 *   item, scraped by its own worker — so N categories × M countries runs
 *   up to `concurrency` of the N×M items truly concurrently. Defaults to
 *   `[country]` for backward compatibility with the single-country form.
 * @param {string} [opts.country] - convenience single-country shorthand,
 *   used only when `countries` isn't provided.
 * @param {number} [opts.concurrency] - 2-8, default 4
 * @param {string} [opts.dateRange]
 * @param {number} [opts.maxResultsPerState]
 * @param {number} [opts.targetLeadCount]
 * @param {boolean} [opts.analyze]
 * @param {boolean} [opts.exportOnly] - skip per-lead Firestore writes
 *   entirely; leads are kept in memory and, once every category finishes,
 *   packaged into one .xlsx workbook (one sheet per category) and uploaded
 *   to Firebase Storage instead — see [buildAndUploadArchive].
 * @param {Function} [opts.scrapeLocationFn] - test-only seam, see leadService.js
 * @param {Function} [opts.saveLeadsFn] - test-only seam; defaults to
 *   `saveLeadsToFirebase`, or the in-memory collector when `exportOnly` is set
 */
export async function startMultiCategorySearch({
  categories,
  countries,
  concurrency = DEFAULT_CONCURRENCY,
  dateRange = '30',
  maxResultsPerState = 150,
  targetLeadCount = 100,
  analyze = false,
  exportOnly = false,
  country = 'US',
  scrapeLocationFn,
  saveLeadsFn,
}) {
  if (!Array.isArray(categories) || !categories.length) {
    throw new Error('categories array is required');
  }
  if (currentJob && currentJob.status !== 'done') {
    const err = new Error('A multi-category search is already running.');
    err.status = 409;
    throw err;
  }

  const uniqueCategories = [...new Set(categories.map((c) => String(c).trim()).filter(Boolean))];
  if (!uniqueCategories.length) {
    throw new Error('categories array is required');
  }

  const countryInput = Array.isArray(countries) && countries.length ? countries : [country];
  const uniqueCountries = [...new Set(countryInput.map((c) => countryMeta(c).code))];
  const multiCountry = uniqueCountries.length > 1;

  const poolSize = clampConcurrency(concurrency);

  const records = {};
  const queue = [];
  for (const category of uniqueCategories) {
    for (const countryCode of uniqueCountries) {
      const key = workKey(category, countryCode);
      const label = multiCountry ? `${category} · ${countryMeta(countryCode).shortName}` : category;
      records[key] = newWorkItemRecord(category, countryCode, label, regionsForCountry(countryCode).length);
      queue.push(key);
    }
  }

  const thisJob = {
    categories: uniqueCategories,
    countries: uniqueCountries,
    concurrency: poolSize,
    dateRange: String(dateRange),
    maxResultsPerState: Number(maxResultsPerState) || 150,
    targetLeadCount: Number(targetLeadCount) || 100,
    analyze: Boolean(analyze),
    exportOnly: Boolean(exportOnly),
    queue,
    records,
    activityLog: [],
    startedAt: Date.now(),
    finishedAt: null,
    status: 'running', // running | done
    cancelled: false,
    paused: false,
    activeWorkers: poolSize,
    browser: null,
    firebaseMutex: new Mutex(),
    collectedLeads: {},
    archiveStatus: exportOnly ? 'pending' : null,
    archiveResult: null,
    archiveError: null,
  };
  thisJob.saveLeadsFn = saveLeadsFn || (exportOnly ? collectInMemory(thisJob) : saveLeadsToFirebase);
  currentJob = thisJob;

  const scopeDesc = multiCountry
    ? `${uniqueCategories.length} categor${uniqueCategories.length === 1 ? 'y' : 'ies'} × ${uniqueCountries.length} countries (${queue.length} total)`
    : `${uniqueCategories.length} categories, ${countryMeta(uniqueCountries[0]).name}`;
  logActivity(thisJob, `Starting multi-category search: ${scopeDesc}, ${poolSize} workers.`);

  thisJob.browser = await launchBrowser();

  const workerIds = Array.from({ length: poolSize }, (_, i) => i + 1);
  Promise.all(workerIds.map((id) => runWorker(id, scrapeLocationFn, thisJob))).catch((err) => {
    console.error('Multi-category worker pool crashed:', err);
    logActivity(thisJob, `Worker pool error: ${err.message}`, 'error');
  });

  return { started: true, categories: uniqueCategories, countries: uniqueCountries, concurrency: poolSize };
}

function categorySnapshot(rec) {
  const now = Date.now();
  const elapsedMs = rec.startedAt ? (rec.finishedAt || now) - rec.startedAt : 0;
  const statesRemaining = Math.max(0, rec.statesTotal - rec.statesDone);
  const avgMsPerState = rec.statesDone > 0 ? elapsedMs / rec.statesDone : null;
  const etaMs =
    avgMsPerState != null && isRunningStatus(rec.status) ? Math.round(avgMsPerState * statesRemaining) : null;
  // A category can finish successfully without visiting every state — it
  // stops early once it hits its target lead count (see `stopAtTarget` in
  // scrapeCategoryNationwide). That's still 100% *done*, so "completed"
  // must show 100% regardless of how many states that took, rather than
  // the states-fraction, which would otherwise stay stuck below 100% even
  // though nothing more will ever happen on this item.
  const progressPercent = rec.status === 'completed'
    ? 100
    : rec.statesTotal > 0
      ? Math.min(100, Math.round((rec.statesDone / rec.statesTotal) * 100))
      : 0;

  return {
    category: rec.category,
    country: rec.country,
    label: rec.label,
    status: rec.status,
    workerId: rec.workerId,
    progressPercent,
    currentState: rec.currentState,
    statesDone: rec.statesDone,
    statesTotal: rec.statesTotal,
    statesRemaining,
    businessesProcessed: rec.businessesProcessed,
    leadsCollected: rec.leadsCollected,
    startedAt: rec.startedAt,
    elapsedMs,
    etaMs,
    lastActivityAt: rec.lastActivityAt,
    warnings: rec.warnings,
    error: rec.error,
    paused: rec.paused,
  };
}

/** Full dashboard snapshot for the status endpoint. Returns `null` if no job has ever run. */
export function getMultiJobSnapshot() {
  const job = currentJob;
  if (!job) return null;

  const records = Object.values(job.records);
  const categorySnapshots = records.map(categorySnapshot);

  const completed = records.filter((r) => r.status === 'completed').length;
  const failed = records.filter((r) => r.status === 'failed').length;
  const cancelled = records.filter((r) => r.status === 'cancelled').length;
  const running = records.filter((r) => isRunningStatus(r.status)).length;
  const queued = records.filter((r) => r.status === 'queued').length;

  const totalStatesDone = records.reduce((sum, r) => sum + r.statesDone, 0);
  const totalStatesPlanned = records.reduce((sum, r) => sum + r.statesTotal, 0);
  const totalStatesRemaining = Math.max(0, totalStatesPlanned - totalStatesDone);
  const totalLeads = records.reduce((sum, r) => sum + r.leadsCollected, 0);
  const totalBusinessesProcessed = records.reduce((sum, r) => sum + r.businessesProcessed, 0);

  const now = Date.now();
  const elapsedMs = (job.finishedAt || now) - job.startedAt;
  const avgMsPerState = totalStatesDone > 0 ? elapsedMs / totalStatesDone : null;
  const overallEtaMs =
    job.status === 'running' && avgMsPerState != null ? Math.round(avgMsPerState * totalStatesRemaining) : null;
  const overallPercent = totalStatesPlanned > 0 ? Math.min(100, Math.round((totalStatesDone / totalStatesPlanned) * 100)) : 0;

  const snapshot = {
    active: job.status === 'running',
    status: job.status,
    concurrency: job.concurrency,
    exportOnly: job.exportOnly,
    archiveStatus: job.archiveStatus,
    archiveResult: job.archiveResult,
    archiveError: job.archiveError,
    overall: {
      percent: overallPercent,
      // Total (category, country) work items — matches completed/failed/
      // running/queued below, which are all counted over `records`.
      totalCategories: records.length,
      totalUniqueCategories: job.categories.length,
      totalCountries: job.countries.length,
      completed,
      failed,
      cancelled,
      running,
      queued,
      totalStatesDone,
      totalStatesRemaining,
      totalLeads,
      totalBusinessesProcessed,
      elapsedMs,
      etaMs: overallEtaMs,
      activeWorkers: job.activeWorkers,
      paused: job.paused,
    },
    categories: categorySnapshots,
    activity: job.activityLog.slice(-100).reverse(),
  };

  if (job.status === 'done') {
    const withDuration = records.filter((r) => r.startedAt && r.finishedAt);
    const avgCategoryMs =
      withDuration.length > 0
        ? withDuration.reduce((sum, r) => sum + (r.finishedAt - r.startedAt), 0) / withDuration.length
        : null;

    snapshot.finalStats = {
      totalExecutionMs: job.finishedAt - job.startedAt,
      totalLeads,
      leadsPerCategory: Object.fromEntries(records.map((r) => [r.label, r.leadsCollected])),
      statesProcessed: totalStatesDone,
      successCount: completed,
      failureCount: failed,
      cancelledCount: cancelled,
      avgMsPerState,
      avgMsPerCategory: avgCategoryMs,
    };
  }

  return snapshot;
}

/**
 * Resolves a (category, country) pair to its work-item key. `country` can
 * be omitted when the job only covers one country (backward-compat with
 * callers that only ever knew about "category") — otherwise it's required
 * to disambiguate which country's run of that category is meant.
 */
function resolveWorkKey(job, category, country) {
  if (country) return workKey(category, countryMeta(country).code);
  if (job.countries.length === 1) return workKey(category, job.countries[0]);
  return null;
}

export function cancelMultiJob() {
  const job = currentJob;
  if (!job || job.status === 'done') return false;
  job.cancelled = true;
  job.paused = false;
  for (const key of job.queue) {
    const rec = job.records[key];
    rec.status = 'cancelled';
    rec.finishedAt = Date.now();
  }
  job.queue = [];
  logActivity(job, 'Cancelling entire job — remaining queued work skipped.', 'warn');
  return true;
}

export function cancelCategory(category, country) {
  const job = currentJob;
  const key = job && resolveWorkKey(job, category, country);
  const rec = key ? job.records[key] : null;
  if (!rec) return false;
  if (rec.status === 'queued') {
    job.queue = job.queue.filter((k) => k !== key);
    rec.status = 'cancelled';
    rec.finishedAt = Date.now();
    logActivity(job, `"${rec.label}" cancelled while queued.`, 'warn');
  } else if (isRunningStatus(rec.status)) {
    rec.cancelled = true;
    rec.paused = false;
    logActivity(job, `Cancelling "${rec.label}" — will stop after the current state.`, 'warn');
  }
  return true;
}

export function pauseMultiJob() {
  const job = currentJob;
  if (!job || job.status === 'done') return false;
  job.paused = true;
  logActivity(job, 'Job paused.', 'warn');
  return true;
}

export function resumeMultiJob() {
  const job = currentJob;
  if (!job || job.status === 'done') return false;
  job.paused = false;
  logActivity(job, 'Job resumed.');
  return true;
}

export function pauseCategory(category, country) {
  const job = currentJob;
  const key = job && resolveWorkKey(job, category, country);
  const rec = key ? job.records[key] : null;
  if (!rec || !isRunningStatus(rec.status)) return false;
  rec.paused = true;
  logActivity(job, `"${rec.label}" paused.`, 'warn');
  return true;
}

export function resumeCategory(category, country) {
  const job = currentJob;
  const key = job && resolveWorkKey(job, category, country);
  const rec = key ? job.records[key] : null;
  if (!rec) return false;
  rec.paused = false;
  logActivity(job, `"${rec.label}" resumed.`);
  return true;
}

/** Exposed for tests only. */
export function _resetMultiJobForTests() {
  currentJob = null;
}
