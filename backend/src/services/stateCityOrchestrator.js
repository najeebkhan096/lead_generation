/**
 * State-by-state, city-by-city scan — the sole scanning engine now that
 * the app is US-only. Distinct from `multiCategoryOrchestrator.js` (kept
 * dormant, not deleted, in case multi-country ever comes back): that one
 * queues (category, country) pairs and lets any worker pick up any of
 * them concurrently. This one is a deliberately staged pipeline instead:
 *
 *   for each category (sequential):
 *     for each state (sequential, alphabetical):
 *       scrape every city in that state, up to `concurrency` at once
 *       -> checkpoint that category's archive (adds this state's sheet)
 *     -> category fully done, archive finalized
 *
 * "Sequential states, parallel cities within one state" is a deliberate
 * choice (not just fewer moving parts): it bounds how many concurrent
 * requests hit Google Maps at once regardless of how big a state's city
 * list is, and it means "state N finished" is always a real, meaningful
 * checkpoint — nothing from state N+1 is ever half-done when state N's
 * data gets saved.
 */

import crypto from 'crypto';
import { launchBrowser } from '../scraper/googleMapsScraper.js';
import { scrapeOneCity } from './leadService.js';
import { US_STATE_CITIES } from '../data/usStateCities.js';
import { Mutex } from '../utils/asyncMutex.js';
import { leadsToXlsxBuffer, xlsxBufferToJson, sheetsToLeadsJson } from './exportService.js';
import { uploadExcelArchive, buildArchiveFileName, getExcelArchive, downloadExcelArchiveBuffer } from './excelArchiveStore.js';

const MIN_CONCURRENCY = 2;
const MAX_CONCURRENCY = 8;
const DEFAULT_CONCURRENCY = 4;
// Listing pages within a city are opened one at a time, so this directly
// sets a city's worst-case duration (up to 45s per listing on a bad
// connection) — 160 favors real thoroughness per city; the live
// "Scanning now" per-city status (see `activity` tracking below) means a
// slow city reads as "still working," not "stuck."
const DEFAULT_MAX_RESULTS_PER_CITY = 160;
const ACTIVITY_LOG_LIMIT = 400;
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

function logActivity(job, message, level = 'info') {
  job.activityLog.push({ timestamp: Date.now(), level, message });
  if (job.activityLog.length > ACTIVITY_LOG_LIMIT) {
    job.activityLog.splice(0, job.activityLog.length - ACTIVITY_LOG_LIMIT);
  }
}

async function waitWhilePaused(job) {
  while (job.paused && !job.cancelled) {
    await sleep(PAUSE_POLL_MS);
  }
}

function newStateRecord(state, cities) {
  return {
    state,
    cities,
    citiesTotal: cities.length,
    covered: [],
    pending: [...cities],
    // Cities a worker has claimed and is actively scraping right now —
    // without this, a claimed city just vanishes from view between being
    // taken off `pending` and landing in `covered`/`failed`, which is
    // exactly what made a running scan look stuck/frozen.
    inProgress: [],
    // city -> short live status string (e.g. "opening listing 4/20"),
    // sourced straight from the scraper's own progress messages.
    activity: {},
    failed: [],
    status: 'pending', // pending | running | done | cancelled
    leadsCollected: 0,
    businessesProcessed: 0,
    startedAt: null,
    finishedAt: null,
  };
}

/** Scrapes every city in `stateRec` with up to `job.concurrency` workers
 * running at once, mutating `stateRec` (covered/pending/inProgress/failed/
 * leads) live as each city starts and finishes — the source of truth the
 * status endpoint reads for the detailed per-state UI. */
async function scanStateCities(job, category, stateRec) {
  stateRec.status = 'running';
  stateRec.startedAt = Date.now();
  logActivity(job, `"${category}" — starting ${stateRec.state} (${stateRec.citiesTotal} cities)`);

  async function worker() {
    while (true) {
      if (job.cancelled) return;
      await waitWhilePaused(job);
      if (job.cancelled) return;
      const city = stateRec.pending[0];
      if (city === undefined) return;
      // Claim it immediately (synchronous, no await before this point in
      // the iteration) so two workers can never grab the same city.
      stateRec.pending.shift();
      stateRec.inProgress.push(city);
      stateRec.activity[city] = 'starting…';

      try {
        const { leads, businessesScraped } = await scrapeOneCity(
          category,
          { city, state: stateRec.state },
          {
            dateRange: job.dateRange,
            maxResults: job.maxResultsPerCity,
            analyze: job.analyze,
            country: 'US',
            browser: job.browser,
            onProgress: (message) => {
              stateRec.activity[city] = message;
            },
            shouldStop: () => job.cancelled,
            scrapeLocationFn: job.scrapeLocationFn,
          }
        );

        (job.collectedLeadsByState[category][stateRec.state] ??= []).push(...leads);
        stateRec.leadsCollected += leads.length;
        stateRec.businessesProcessed += businessesScraped;
        stateRec.covered.push(city);
        logActivity(
          job,
          `"${category}" · ${stateRec.state} · ${city} — ${leads.length} lead${leads.length === 1 ? '' : 's'} (${stateRec.covered.length + stateRec.failed.length}/${stateRec.citiesTotal} cities)`
        );
      } catch (err) {
        stateRec.failed.push(city);
        logActivity(job, `"${category}" · ${stateRec.state} · ${city} — failed: ${err.message}`, 'warn');
      } finally {
        const idx = stateRec.inProgress.indexOf(city);
        if (idx !== -1) stateRec.inProgress.splice(idx, 1);
        delete stateRec.activity[city];
      }
    }
  }

  const poolSize = Math.min(job.concurrency, stateRec.citiesTotal || 1);
  await Promise.all(Array.from({ length: poolSize }, () => worker()));

  // Only genuinely 'done' if every city was actually covered — a cancel
  // mid-state stops workers between cities (see `shouldStop` above), which
  // can leave `pending` non-empty here. Marking it 'cancelled' instead of
  // 'done' keeps it correctly excluded from `completedStates`, so a later
  // resume re-scans this state's remaining cities instead of skipping it.
  stateRec.status = stateRec.pending.length === 0 ? 'done' : 'cancelled';
  stateRec.finishedAt = Date.now();
  logActivity(
    job,
    `"${category}" — ${stateRec.state} ${stateRec.status === 'done' ? 'complete' : 'cancelled'}: ${stateRec.leadsCollected} leads across ${stateRec.covered.length}/${stateRec.citiesTotal} cities` +
      (stateRec.failed.length ? ` (${stateRec.failed.length} failed)` : '')
  );
}

/** Rebuilds and re-uploads one category's workbook — one sheet per state
 * that has any leads so far, upserted in place (same Storage object/
 * Firestore doc via the archive's fixed id/fileName). Called after every
 * state finishes (checkpoint) and once more when the category itself is
 * fully done (final). */
async function uploadCategoryArchiveNow(job, category, { isFinal }) {
  const archive = job.categoryArchives[category];
  if (!archive) return;

  // `archive.allStates` — the FULL 51-state list this category's file
  // should ultimately cover — not `job.categoryStates[category]`, which
  // for a resumed run only holds whichever states were still missing.
  // Mirrors `multiCategoryOrchestrator.js`'s `allCountries`/`countries`
  // split for the same reason: a fresh (non-resumed) run has the two
  // equal, so this is a no-op change in that case.
  const sheets = [];
  for (const state of archive.allStates) {
    const leads = job.collectedLeadsByState[category][state];
    if (leads && leads.length) sheets.push({ name: state, leads });
  }
  if (!sheets.length) {
    if (isFinal) archive.status = 'done';
    return;
  }

  const totalLeads = sheets.reduce((sum, s) => sum + s.leads.length, 0);
  const totalBusinessesProcessed =
    (archive.priorBusinessesProcessed || 0) +
    job.categoryStates[category].reduce((sum, s) => sum + s.businessesProcessed, 0);

  archive.status = 'building';
  try {
    const buffer = await leadsToXlsxBuffer(sheets);
    const record = await uploadExcelArchive({
      id: archive.id,
      buffer,
      fileName: archive.fileName,
      categories: [category],
      countries: ['US'],
      totalLeads,
      totalBusinessesProcessed,
      status: isFinal ? 'complete' : 'partial',
      category,
      completedCountries: [...archive.completedStates],
      dateRange: job.dateRange,
      maxResultsPerState: job.maxResultsPerCity,
      targetLeadCount: null,
      analyze: job.analyze,
    });

    archive.status = isFinal ? 'done' : 'partial';
    archive.result = record;
    archive.error = null;
    if (isFinal) {
      logActivity(job, `"${category}" archive finalized: ${record.fileName} (${totalLeads} leads, ${archive.completedStates.size} states).`);
    }
  } catch (err) {
    archive.status = archive.result ? 'partial' : 'failed';
    archive.error = err.message;
    logActivity(job, `"${category}" archive ${isFinal ? 'final ' : 'checkpoint '}upload failed: ${err.message}`, 'error');
  }
}

async function runJob(job) {
  try {
    for (const category of job.categories) {
      if (job.cancelled) break;
      job.currentCategory = category;
      job.categoryStatus[category] = 'running';
      const archive = job.categoryArchives[category];

      // Tracks whether this run covered every state it was responsible
      // for — a resumed run's "every state" is just its own missing
      // subset, not necessarily all 51. Only a category that finishes
      // that fully gets its archive finalized as 'complete'; a cancelled
      // category is left exactly as its last checkpoint ('partial'), so
      // it stays resumable instead of being wrongly marked done.
      let fullyCompleted = true;
      for (const stateRec of job.categoryStates[category]) {
        if (job.cancelled) {
          fullyCompleted = false;
          break;
        }
        await waitWhilePaused(job);
        if (job.cancelled) {
          fullyCompleted = false;
          break;
        }

        await scanStateCities(job, category, stateRec);
        if (stateRec.status === 'done') {
          archive.completedStates.add(stateRec.state);
        } else {
          fullyCompleted = false;
        }
        await job.archiveMutexes[category].runExclusive(() => uploadCategoryArchiveNow(job, category, { isFinal: false }));
      }

      job.categoryStatus[category] = fullyCompleted ? 'done' : 'cancelled';
      if (fullyCompleted) {
        await job.archiveMutexes[category].runExclusive(() => uploadCategoryArchiveNow(job, category, { isFinal: true }));
      }
    }
  } catch (err) {
    logActivity(job, `Job error: ${err.message}`, 'error');
  }

  try {
    await job.browser?.close();
  } catch {
    // ignore
  }

  job.finishedAt = Date.now();
  job.status = 'done';
  logActivity(job, `Scan finished in ${Math.round((job.finishedAt - job.startedAt) / 1000)}s.`);
}

/**
 * @param {object} opts
 * @param {string[]} opts.categories
 * @param {number} [opts.concurrency] - 2-8, default 4. Workers scan cities
 *   within whichever ONE state is currently active, not across states.
 * @param {string} [opts.dateRange]
 * @param {number} [opts.maxResultsPerCity]
 * @param {boolean} [opts.analyze]
 * @param {Function} [opts.scrapeLocationFn] - test-only seam, see leadService.js
 * @param {{state: string, cities: string[]}[]} [opts.statesOverride] -
 *   test-only seam; defaults to the real `US_STATE_CITIES` data. Also how
 *   `resumeStateCityScan` scopes a run to just the missing states.
 * @param {Object.<string, object>} [opts.resumeArchives] - internal, set
 *   by `resumeStateCityScan` — keyed by category, points a fresh job's
 *   `categoryArchives[category]` at an *existing* archive's id/fileName
 *   (so checkpoints/finalize upsert that same doc) and pre-seeds
 *   already-scraped states' leads back into `collectedLeadsByState`.
 */
export async function startStateCityScan({
  categories,
  concurrency = DEFAULT_CONCURRENCY,
  dateRange = '30',
  maxResultsPerCity = DEFAULT_MAX_RESULTS_PER_CITY,
  analyze = false,
  scrapeLocationFn,
  statesOverride,
  resumeArchives,
}) {
  if (!Array.isArray(categories) || !categories.length) {
    throw new Error('categories array is required');
  }
  if (currentJob && currentJob.status !== 'done') {
    const err = new Error('A scan is already running.');
    err.status = 409;
    throw err;
  }

  const uniqueCategories = [...new Set(categories.map((c) => String(c).trim()).filter(Boolean))];
  if (!uniqueCategories.length) {
    throw new Error('categories array is required');
  }
  const states = statesOverride || US_STATE_CITIES;
  if (!states.length) {
    throw new Error('No state/city data available — check usStateCities.js');
  }

  const poolSize = clampConcurrency(concurrency);

  const categoryStates = {};
  const categoryStatus = {};
  const collectedLeadsByState = {};
  const categoryArchives = {};
  const archiveMutexes = {};
  for (const category of uniqueCategories) {
    const resume = resumeArchives?.[category];
    categoryStates[category] = states.map((s) => newStateRecord(s.state, s.cities));
    categoryStatus[category] = 'pending';
    collectedLeadsByState[category] = {};
    categoryArchives[category] = {
      id: resume?.id || crypto.randomUUID(),
      fileName: resume?.fileName || buildArchiveFileName({ categories: [category], countries: ['US'] }),
      // The FULL state set this category's file should cover — for a
      // resume this is the original 51, not just the (smaller) set this
      // particular job run is re-scanning.
      allStates: resume?.allStates || states.map((s) => s.state),
      completedStates: new Set(resume?.completedStates || []),
      priorBusinessesProcessed: resume?.priorBusinessesProcessed || 0,
      status: 'pending', // pending | building | partial | done | failed
      result: null,
      error: null,
    };
    archiveMutexes[category] = new Mutex();

    for (const [state, leads] of Object.entries(resume?.seedLeadsByState || {})) {
      collectedLeadsByState[category][state] = leads;
    }
  }

  const thisJob = {
    categories: uniqueCategories,
    concurrency: poolSize,
    dateRange: String(dateRange),
    maxResultsPerCity: Math.max(4, Number(maxResultsPerCity) || DEFAULT_MAX_RESULTS_PER_CITY),
    analyze: Boolean(analyze),
    scrapeLocationFn,
    status: 'running', // running | done
    cancelled: false,
    paused: false,
    startedAt: Date.now(),
    finishedAt: null,
    browser: null,
    currentCategory: uniqueCategories[0],
    categoryStates,
    categoryStatus,
    collectedLeadsByState,
    categoryArchives,
    archiveMutexes,
    activityLog: [],
  };

  currentJob = thisJob;
  const totalCities = categoryStates[uniqueCategories[0]].reduce((sum, s) => sum + s.citiesTotal, 0);
  logActivity(
    thisJob,
    `Starting scan: ${uniqueCategories.length} categor${uniqueCategories.length === 1 ? 'y' : 'ies'} × ${categoryStates[uniqueCategories[0]].length} states (${totalCities} cities each), ${poolSize} workers.`
  );

  thisJob.browser = await launchBrowser();
  runJob(thisJob).catch((err) => {
    console.error('State/city scan crashed:', err);
    logActivity(thisJob, `Scan crashed: ${err.message}`, 'error');
  });

  return { started: true, categories: uniqueCategories, concurrency: poolSize, totalStates: categoryStates[uniqueCategories[0]].length };
}

/**
 * Picks a `status: 'partial'` category archive back up — e.g. after the
 * backend crashed, was restarted, or the scan was cancelled mid-way.
 * Re-scans *only* the states that never finished; already-covered states
 * are recovered straight from the archive's current workbook (each sheet
 * is already named by state, so no lookup is needed) and merged back into
 * the same archive doc/Storage file once the remaining states are done —
 * the end result reads exactly like the original scan simply finished.
 */
export async function resumeStateCityScan({ archiveId, concurrency, scrapeLocationFn, allStatesOverride } = {}) {
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

  const stateData = allStatesOverride || US_STATE_CITIES;
  const allStates = stateData.map((s) => s.state);

  const downloaded = await downloadExcelArchiveBuffer(archiveId);
  const sheets = downloaded ? await xlsxBufferToJson(downloaded.buffer) : [];
  const seedLeadsByState = {};
  const statesWithData = [];
  for (const sheet of sheets) {
    if (!allStates.includes(sheet.name) || !sheet.rows.length) continue;
    seedLeadsByState[sheet.name] = sheetsToLeadsJson([sheet], `resume-${archiveId}-${sheet.name}`);
    statesWithData.push(sheet.name);
  }

  const completedStates = archive.completedCountries?.length ? archive.completedCountries : statesWithData;
  const missingStates = allStates.filter((s) => !completedStates.includes(s));
  if (!missingStates.length) {
    const err = new Error('Nothing left to resume — every state already has data. Try re-checking the archive list.');
    err.status = 400;
    throw err;
  }

  const result = await startStateCityScan({
    categories: [category],
    concurrency,
    dateRange: archive.dateRange || '30',
    maxResultsPerCity: archive.maxResultsPerState || DEFAULT_MAX_RESULTS_PER_CITY,
    analyze: archive.analyze || false,
    scrapeLocationFn,
    statesOverride: stateData.filter((s) => missingStates.includes(s.state)),
    resumeArchives: {
      [category]: {
        id: archive.id,
        fileName: archive.fileName,
        allStates,
        completedStates,
        priorBusinessesProcessed: archive.totalBusinessesProcessed || 0,
        seedLeadsByState,
      },
    },
  });

  logActivity(currentJob, `Resuming "${category}" — ${missingStates.length} of ${allStates.length} states remaining.`);
  return result;
}

export function getStateCityJobSnapshot() {
  const job = currentJob;
  if (!job) return null;

  const categories = job.categories.map((category) => {
    const states = job.categoryStates[category];
    const archive = job.categoryArchives[category];
    const statesDone = states.filter((s) => s.status === 'done').length;
    const citiesTotal = states.reduce((sum, s) => sum + s.citiesTotal, 0);
    const citiesDone = states.reduce((sum, s) => sum + s.covered.length + s.failed.length, 0);
    const leadsCollected = states.reduce((sum, s) => sum + s.leadsCollected, 0);
    const businessesProcessed = states.reduce((sum, s) => sum + s.businessesProcessed, 0);

    return {
      category,
      status: job.categoryStatus[category],
      statesTotal: states.length,
      statesDone,
      citiesTotal,
      citiesDone,
      leadsCollected,
      businessesProcessed,
      archive: { status: archive.status, result: archive.result, error: archive.error },
      states: states.map((s) => ({
        state: s.state,
        status: s.status,
        citiesTotal: s.citiesTotal,
        covered: s.covered,
        pending: s.pending,
        inProgress: s.inProgress.map((city) => ({ city, message: s.activity[city] || '' })),
        failed: s.failed,
        leadsCollected: s.leadsCollected,
        businessesProcessed: s.businessesProcessed,
        startedAt: s.startedAt,
        finishedAt: s.finishedAt,
      })),
    };
  });

  return {
    active: job.status === 'running',
    status: job.status,
    concurrency: job.concurrency,
    currentCategory: job.currentCategory,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
    paused: job.paused,
    categories,
    activity: job.activityLog.slice(-150).reverse(),
  };
}

export function cancelStateCityJob() {
  const job = currentJob;
  if (!job || job.status === 'done') return false;
  job.cancelled = true;
  job.paused = false;
  logActivity(job, 'Cancelling scan — will stop after the current city finishes.', 'warn');
  return true;
}

export function pauseStateCityJob() {
  const job = currentJob;
  if (!job || job.status === 'done') return false;
  job.paused = true;
  logActivity(job, 'Scan paused.', 'warn');
  return true;
}

export function resumeStateCityJob() {
  const job = currentJob;
  if (!job || job.status === 'done') return false;
  job.paused = false;
  logActivity(job, 'Scan resumed.');
  return true;
}

/** Exposed for tests only. */
export function _resetStateCityJobForTests() {
  currentJob = null;
}
