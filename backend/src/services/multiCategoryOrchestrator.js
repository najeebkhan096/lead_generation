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

import crypto from 'crypto';
import { launchBrowser } from '../scraper/googleMapsScraper.js';
import { scrapeCategoryNationwide } from './leadService.js';
import { saveLeadsToFirebase } from './firebaseLeadStore.js';
import { setLastSearch } from '../utils/memoryStore.js';
import { countryMeta, countryCodeForName, regionsForCountry } from '../data/countries.js';
import { Mutex } from '../utils/asyncMutex.js';
import { leadsToXlsxBuffer, xlsxBufferToJson, sheetsToLeadsJson } from './exportService.js';
import { uploadExcelArchive, buildArchiveFileName, getExcelArchive, downloadExcelArchiveBuffer } from './excelArchiveStore.js';

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

function isTerminalStatus(status) {
  return status === 'completed' || status === 'failed' || status === 'cancelled';
}

/** True once every country queued for `category` has reached a terminal
 * (completed/failed/cancelled) state — the trigger for finalizing that
 * category's own archive, independently of every other category. */
function categoryFullyDone(thisJob, category) {
  return thisJob.countries.every((countryCode) => {
    const rec = thisJob.records[workKey(category, countryCode)];
    return rec && isTerminalStatus(rec.status);
  });
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

    if (thisJob.exportOnly) {
      const archive = thisJob.categoryArchives[rec.category];
      // Recorded regardless of outcome (completed/failed/cancelled all
      // count as "handled") and persisted to Firestore on every upload —
      // this is what makes a country-not-yet-attempted-at-crash-time
      // distinguishable from one already scraped, so a later resume only
      // re-does the work that never actually finished.
      archive?.completedCountries.add(rec.country);
      // The synchronous status update above (no `await` in between) means
      // whichever worker finishes the last country for this category is
      // the only one that can observe `categoryFullyDone` flip true here —
      // safe to gate finalization on it without the mutex.
      if (archive && !archive.finalized && categoryFullyDone(thisJob, rec.category)) {
        archive.finalized = true;
        // Tracked on the archive (not just fired-and-forgotten) so
        // `finishJob`'s safety net can await this exact in-flight upload
        // instead of seeing `finalized: true` and wrongly assuming there's
        // nothing left to wait for — otherwise the job could report
        // 'done' with the very last category's archive still 'building'.
        archive.finalizePromise = archive.mutex
          .runExclusive(() => uploadCategoryArchiveNow(thisJob, rec.category, { isFinal: true }))
          .catch(() => {});
      } else {
        checkpointCategoryArchive(thisJob, rec.category);
      }
    }
  }

  thisJob.activeWorkers -= 1;
  if (thisJob.activeWorkers === 0) await finishJob(thisJob);
}

/**
 * Uploads (or re-uploads, in place — same Storage path/Firestore doc via
 * the category's own fixed `id`/`fileName`) one category's own workbook:
 * one sheet per country, covering only that category. Each category gets
 * its own archive, finalized (`isFinal: true`) the moment every country
 * queued for it reaches a terminal state — independently of whatever
 * every other category is still doing (see the call site in `runWorker`).
 * Also called as a mid-category checkpoint (`isFinal: false`, after each
 * of that category's countries finishes but before the category as a
 * whole is done) so a crash loses at most the one country in flight.
 * Always run through the category's own mutex (see call sites) so
 * concurrent updates to the same category never race each other's upload.
 */
async function uploadCategoryArchiveNow(thisJob, category, { isFinal }) {
  const archive = thisJob.categoryArchives[category];
  if (!archive) return;

  // `archive.allCountries` — the FULL originally-requested set for this
  // category — not `thisJob.countries`, which for a resumed run only
  // covers the countries still missing. A fresh (non-resumed) job has the
  // two equal, so this is a no-op change in that case.
  const sheets = [];
  for (const countryCode of archive.allCountries) {
    const leads = thisJob.collectedLeads[workKey(category, countryCode)];
    if (leads && leads.length) sheets.push({ name: countryMeta(countryCode).name, leads });
  }
  if (!sheets.length) {
    // Finished (or checkpointing) with zero leads collected — nothing to
    // upload, but a final call must still leave the status settled instead
    // of stuck at 'pending'/'building' forever.
    if (isFinal) archive.status = 'done';
    return;
  }

  const totalLeads = sheets.reduce((sum, s) => sum + s.leads.length, 0);
  // This run's own contribution, plus whatever a resumed run's earlier
  // (now-crashed) attempt already reported — that history only exists on
  // the archive doc itself, not in this fresh in-memory job.
  const totalBusinessesProcessed =
    (archive.priorBusinessesProcessed || 0) +
    thisJob.countries.reduce((sum, countryCode) => {
      const rec = thisJob.records[workKey(category, countryCode)];
      return sum + (rec?.businessesProcessed || 0);
    }, 0);

  archive.status = 'building';
  try {
    const buffer = await leadsToXlsxBuffer(sheets);
    const record = await uploadExcelArchive({
      id: archive.id,
      buffer,
      fileName: archive.fileName,
      categories: [category],
      countries: archive.allCountries,
      totalLeads,
      totalBusinessesProcessed,
      status: isFinal ? 'complete' : 'partial',
      category,
      completedCountries: [...archive.completedCountries],
      dateRange: thisJob.dateRange,
      maxResultsPerState: thisJob.maxResultsPerState,
      targetLeadCount: thisJob.targetLeadCount,
      analyze: thisJob.analyze,
    });

    archive.status = isFinal ? 'done' : 'partial';
    archive.result = record;
    archive.error = null;
    if (isFinal) {
      logActivity(
        thisJob,
        `"${category}" finished across all ${archive.allCountries.length} countr${archive.allCountries.length === 1 ? 'y' : 'ies'} — archive uploaded: ${record.fileName} (${totalLeads} leads).`
      );
    }
  } catch (err) {
    // Don't regress the UI to a dead end over one failed upload attempt —
    // if an earlier checkpoint already succeeded, keep it visible/
    // downloadable; the next checkpoint (or the final one) retries anyway.
    archive.status = archive.result ? 'partial' : 'failed';
    archive.error = err.message;
    logActivity(thisJob, `"${category}" archive ${isFinal ? 'final ' : 'checkpoint '}upload failed: ${err.message}`, 'error');
  }
}

function checkpointCategoryArchive(thisJob, category) {
  const archive = thisJob.categoryArchives[category];
  if (!archive) return;
  archive.mutex.runExclusive(() => uploadCategoryArchiveNow(thisJob, category, { isFinal: false })).catch(() => {
    // uploadCategoryArchiveNow already catches and records failures on the
    // archive — this only guards the (unexpected) case runExclusive throws.
  });
}

async function finishJob(thisJob) {
  if (thisJob.finishedAt !== null) return;
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
    // Safety net — every category should already have finalized its own
    // archive the instant its last country reached a terminal state (see
    // `runWorker`), but a category cancelled entirely while still queued
    // (never picked up by any worker) never passes through that path.
    // Idempotent via `archive.finalized`, so this is a no-op for every
    // category that already finished normally.
    await Promise.all(
      thisJob.categories.map((category) => {
        const archive = thisJob.categoryArchives[category];
        // Already finalized (normal path, from runWorker) — wait for that
        // exact in-flight upload rather than assuming it's already done.
        if (archive.finalized) return archive.finalizePromise ?? null;
        archive.finalized = true;
        archive.finalizePromise = archive.mutex.runExclusive(() => uploadCategoryArchiveNow(thisJob, category, { isFinal: true }));
        return archive.finalizePromise;
      })
    );
  }

  // Only flip to 'done' once every category archive has actually settled
  // (all the awaits above are done) — so a status poll never has to reason
  // about "job done but an archive still building", it can just trust that
  // status === 'done' means everything, archives included, is final.
  thisJob.status = 'done';
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
 *   entirely; leads are kept in memory and packaged into one .xlsx workbook
 *   *per category* (one sheet per country within it), uploaded to Firebase
 *   Storage the moment that category finishes across every country —
 *   independently of every other category, which may still be running —
 *   see [uploadCategoryArchiveNow].
 * @param {Function} [opts.scrapeLocationFn] - test-only seam, see leadService.js
 * @param {Function} [opts.saveLeadsFn] - test-only seam; defaults to
 *   `saveLeadsToFirebase`, or the in-memory collector when `exportOnly` is set
 * @param {Object.<string, object>} [opts.resumeArchives] - internal, set by
 *   `resumeCategoryArchive` — keyed by category, each entry points a fresh
 *   job's `categoryArchives[category]` at an *existing* archive's id/
 *   fileName (so its checkpoints/finalize upsert that same doc instead of
 *   creating a new one) and pre-seeds already-scraped countries' leads back
 *   into `collectedLeads`, so this job only needs to actually scrape
 *   whatever's left in `countries`/`categories`.
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
  resumeArchives,
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
    // One archive per category (not one per job) — each covers every
    // selected country as its own sheet, and finalizes (uploads) the
    // instant that category finishes across all of them, independently of
    // whatever every other category is still doing. `id`/`fileName` are
    // fixed once up front so every checkpoint for a category upserts the
    // same Storage object + Firestore doc instead of creating a new entry.
    categoryArchives: exportOnly
      ? Object.fromEntries(
          uniqueCategories.map((category) => {
            const resume = resumeArchives?.[category];
            return [
              category,
              {
                id: resume?.id || crypto.randomUUID(),
                fileName: resume?.fileName || buildArchiveFileName({ categories: [category], countries: uniqueCountries }),
                // The FULL country set this category's file should cover —
                // for a resume this is the original request, not just the
                // (smaller) set this particular job run is re-scraping.
                allCountries: resume?.allCountries || uniqueCountries,
                completedCountries: new Set(resume?.completedCountries || []),
                priorBusinessesProcessed: resume?.priorBusinessesProcessed || 0,
                mutex: new Mutex(),
                status: 'pending', // pending | building | partial | done | failed
                result: null,
                error: null,
                finalized: false,
                finalizePromise: null,
              },
            ];
          })
        )
      : {},
  };
  thisJob.saveLeadsFn = saveLeadsFn || (exportOnly ? collectInMemory(thisJob) : saveLeadsToFirebase);

  // Seed already-scraped countries' leads back into this fresh job's memory
  // — pulled from the archive's existing workbook by `resumeCategoryArchive`
  // — so the merged file this run finalizes still includes them, even
  // though this run never re-scrapes them.
  if (resumeArchives) {
    for (const [category, resume] of Object.entries(resumeArchives)) {
      for (const [countryCode, leads] of Object.entries(resume.seedLeadsByCountry || {})) {
        thisJob.collectedLeads[workKey(category, countryCode)] = leads;
      }
    }
  }

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

/**
 * Picks a `status: 'partial'` category archive back up — e.g. after the
 * backend crashed/restarted mid-scan and stranded it (jobs are in-memory
 * only, so a restart alone can never resume anything on its own). Scrapes
 * *only* the countries that never finished, re-downloads the archive's
 * current workbook to recover already-scraped countries' leads (since
 * those only ever lived in the crashed job's memory), and finalizes back
 * into the *same* archive doc/Storage file once the remaining countries
 * are done — so the end result is identical to the original scan having
 * simply completed, not a second file to reconcile.
 *
 * Archives created before this feature existed won't have
 * `completedCountries`/scan-params stored — falls back to deriving
 * "already done" from the workbook's actual sheets, and to this app's
 * normal scan defaults, so even those older stuck archives are resumable.
 */
export async function resumeCategoryArchive({ archiveId, concurrency, scrapeLocationFn } = {}) {
  if (!archiveId) throw new Error('archiveId is required');

  const archive = await getExcelArchive(archiveId);
  if (!archive) {
    const err = new Error('Archive not found');
    err.status = 404;
    throw err;
  }
  if (archive.status !== 'partial') {
    const err = new Error(`This archive is "${archive.status}" — only "partial" (in-progress) archives can be resumed.`);
    err.status = 400;
    throw err;
  }
  const category = archive.category;
  if (!category) {
    const err = new Error('This archive has no category recorded — cannot resume.');
    err.status = 400;
    throw err;
  }

  // Recover whatever's already in the workbook — the source of truth for
  // "which countries actually have data", regardless of what
  // `completedCountries` says (older archives never wrote that field, and
  // even on new ones this is a cheap, load-bearing cross-check rather than
  // blindly trusting stored state).
  const downloaded = await downloadExcelArchiveBuffer(archiveId);
  const sheets = downloaded ? await xlsxBufferToJson(downloaded.buffer) : [];
  const seedLeadsByCountry = {};
  const countriesWithData = [];
  for (const sheet of sheets) {
    const code = countryCodeForName(sheet.name);
    if (!code || !sheet.rows.length) continue;
    seedLeadsByCountry[code] = sheetsToLeadsJson([sheet], `resume-${archiveId}-${code}`);
    countriesWithData.push(code);
  }

  const completedCountries = archive.completedCountries?.length ? archive.completedCountries : countriesWithData;
  const missingCountries = archive.countries.filter((c) => !completedCountries.includes(c));
  if (!missingCountries.length) {
    const err = new Error('Nothing left to resume — every country already has data. Try re-checking the archive list.');
    err.status = 400;
    throw err;
  }

  const result = await startMultiCategorySearch({
    categories: [category],
    countries: missingCountries,
    concurrency,
    exportOnly: true,
    dateRange: archive.dateRange || '30',
    maxResultsPerState: archive.maxResultsPerState || 150,
    targetLeadCount: archive.targetLeadCount || 100,
    analyze: archive.analyze || false,
    scrapeLocationFn,
    resumeArchives: {
      [category]: {
        id: archive.id,
        fileName: archive.fileName,
        allCountries: archive.countries,
        completedCountries,
        priorBusinessesProcessed: archive.totalBusinessesProcessed || 0,
        seedLeadsByCountry,
      },
    },
  });

  logActivity(currentJob, `Resuming "${category}" — ${missingCountries.length} of ${archive.countries.length} countries remaining.`);
  return result;
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
    // One entry per category, each with its own independent archive
    // lifecycle — see `uploadCategoryArchiveNow`. Empty for non-exportOnly
    // jobs (leads went straight to Firestore, nothing to archive).
    categoryArchives: job.exportOnly
      ? job.categories.map((category) => {
          const archive = job.categoryArchives[category];
          return {
            category,
            status: archive.status,
            result: archive.result,
            error: archive.error,
          };
        })
      : [],
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
