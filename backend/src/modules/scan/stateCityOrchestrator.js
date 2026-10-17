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
import { launchBrowser, checkBrowserSignedIn, probeGoogleMaps } from '../../scraper/googleMapsScraper.js';
import { GoogleBlockedError } from '../../scraper/googleBlock.js';
import { sharedPace, _resetSharedPace } from '../../scraper/rateLimit.js';
import { buildCoverage, isCoverageTier } from '../../data/usCoverage.js';
import { completedCitiesFromStates, placeIdsFromLeads, applyResumeProgress, checkpointDue } from './scanProgress.js';
import { scrapeOneCity } from './leadService.js';
import { Mutex } from '../../lib/asyncMutex.js';
import { leadsToXlsxBuffer, xlsxBufferToJson, sheetsToLeadsJson } from '../archive/exportService.js';
import {
  uploadExcelArchive,
  buildArchiveFileName,
  getExcelArchive,
  downloadExcelArchiveBuffer,
  deleteExcelArchive,
} from '../archive/excelArchiveStore.js';
import { describeSortDiagnostics, resetSortDiagnostics, getSortDiagnostics } from '../../scraper/reviewSort.js';

// How fast pages are opened is set by the shared pace (see rateLimit.js), not by
// the worker count; workers only need to be numerous enough to keep that pace
// fed (pace x time to read a business / 60). Before the pace existed, 10
// workers collapsed and got the network blocked; with every page open metered
// by the pace they cannot out-run it, so 10 is allowed. The early brake slows
// the pace if the extra tabs start failing.
const MIN_CONCURRENCY = 1;
const MAX_CONCURRENCY = 10;
const DEFAULT_CONCURRENCY = 8;

/** How long a blocked scan waits before it first checks whether Google is serving results again. */
const BLOCK_COOLDOWN_MS = Number(process.env.MAPS_BLOCK_COOLDOWN_MINUTES || 10) * 60 * 1000;
const BLOCK_COOLDOWN_MAX_MS = 60 * 60 * 1000;

/** Tries per city before it is recorded as failed. */
const CITY_ATTEMPTS = 2;
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

/**
 * Google is showing its "unusual traffic" check. Stop opening pages, say so,
 * and (once) start a watcher that checks, with growing gaps, whether Google is
 * serving results again, then resumes the scan by itself. Nothing is retried
 * through the check and nothing tries to get past it.
 */
function enterBlockedPause(job, err) {
  if (job.blocked) return; // already paused for it
  job.pace?.noteBlocked?.(); // Google asked for less: find a lower pace
  job.blocked = { since: Date.now(), retryAt: Date.now() + (job.blockCooldownMs ?? BLOCK_COOLDOWN_MS), checks: 0 };
  job.paused = true;
  logActivity(
    job,
    `Google is showing its "unusual traffic" check for this network, so the scan is PAUSED. It will check again in ` +
      `${Math.round((job.blockCooldownMs ?? BLOCK_COOLDOWN_MS) / 60000)} min and continue by itself once Google serves results. ` +
      'Nothing was lost: the city it was on will be redone. (' + (err?.message || 'blocked').slice(0, 80) + ')',
    'error'
  );
  watchForUnblock(job).catch((e) => logActivity(job, `Block watcher failed: ${e.message}`, 'error'));
}

async function watchForUnblock(job) {
  let wait = job.blockCooldownMs ?? BLOCK_COOLDOWN_MS;
  while (job.blocked && !job.cancelled) {
    job.blocked.retryAt = Date.now() + wait;
    // Sleep in short steps so a Cancel is noticed promptly.
    const until = job.blocked.retryAt;
    while (Date.now() < until && !job.cancelled) await sleep(Math.min(1000, Math.max(5, until - Date.now())));
    if (job.cancelled) return;

    job.blocked.checks += 1;
    const probe = job.probeFn ? await job.probeFn() : await probeGoogleMaps(job.browser);
    if (probe === 'ok') {
      logActivity(job, 'Google is serving results again. Scan resumed.');
      job.blocked = null;
      job.paused = false;
      return;
    }
    wait = Math.min(Math.round(wait * 1.5), BLOCK_COOLDOWN_MAX_MS);
    logActivity(job, `Google still shows its check (${probe}). Next look in ${Math.round(wait / 60000) || '<1'} min.`, 'warn');
  }
}

/**
 * A scan can run for a day, so the browser it drives will eventually die (a
 * crash, the Mac sleeping, memory). If it has, start a new one before the next
 * city instead of letting every city fail against a dead browser. One restart
 * at a time, however many workers notice.
 */
async function ensureBrowser(job, launch = launchBrowser) {
  if (job.scrapeLocationFn) return; // tests inject the scraper
  const b = job.browser;
  const alive = !b ? false : typeof b.isAlive === 'function' ? b.isAlive() : typeof b.isConnected === 'function' ? b.isConnected() : true;
  if (alive) return;
  job.browserRestart ??= (async () => {
    logActivity(job, 'The scan\'s browser stopped; starting a new one.', 'warn');
    await b?.close?.().catch(() => {});
    job.browser = await launch();
  })().finally(() => {
    job.browserRestart = null;
  });
  await job.browserRestart;
}

/** Test hook. */
export { ensureBrowser as _ensureBrowserForTests };

/** A fresh browser between states keeps a very long scan from bloating one Chrome. */
async function recycleBrowser(job) {
  if (job.scrapeLocationFn || job.cancelled) return;
  try {
    await job.browser?.close?.().catch(() => {});
    job.browser = await launchBrowser();
  } catch (err) {
    logActivity(job, `Could not start a fresh browser (${err.message}); will retry before the next city.`, 'warn');
    job.browser = null; // ensureBrowser starts one
  }
}

/**
 * After each covered city: save progress now and then, so a restart loses
 * minutes, not hours. Never blocks a worker and never runs two at once.
 */
function noteCityCovered(job, category) {
  job.pace?.noteHealthy?.();
  job.checkpoint ??= {};
  const cp = (job.checkpoint[category] ??= { lastAt: Date.now(), citiesSince: 0, running: false });
  cp.citiesSince += 1;
  if (cp.running || !checkpointDue({ now: Date.now(), lastAt: cp.lastAt, citiesSince: cp.citiesSince })) return;
  if (!job.checkpointFn) return;
  cp.running = true;
  Promise.resolve(job.checkpointFn(category))
    .catch(() => {})
    .finally(() => {
      cp.lastAt = Date.now();
      cp.citiesSince = 0;
      cp.running = false;
    });
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
    firebaseLeadsSaved: 0,
    // Kept (always 0) so the status payload keeps its shape: no-website
    // businesses are no longer scanned for.
    websiteLeadsFound: 0,
    // Businesses in this state whose reviews could not be proven fully read,
    // and listings that could not be opened at all (see scrapeOneCity).
    incompleteBusinesses: 0,
    skippedListings: 0,
    // Listings already read for a neighbouring city (each business is read once).
    duplicatesSkipped: 0,
    // Listings whose rating and review count prove they cannot hold a 1-star review.
    prefiltered: 0,
    // city -> how many times it has been tried (a failed city is retried).
    attempts: {},
    startedAt: null,
    finishedAt: null,
  };
}

/** Test hooks: the per-state scanner and its record shape. */
export { scanStateCities as _scanStateCities, newStateRecord as _newStateRecord };

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
        await ensureBrowser(job);
        const { leads, businessesScraped, reviewIssues, skippedListings, duplicatesSkipped, prefiltered } = await scrapeOneCity(
          category,
          { city, state: stateRec.state, center: job.citySpecs?.[stateRec.state]?.[city] },
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
            seenPlaceIds: job.seenPlaces?.[category],
          }
        );

        // Cancelled while this city was being read: its results are partial, so
        // keep none of them and leave the city for a Resume.
        if (job.cancelled && !job.stoppedReason) {
          stateRec.pending.unshift(city);
          return;
        }

        // Google asked to sign in while reading reviews: the session is
        // missing or has expired, so every further business would be read
        // without sorting and its 1-star reviews missed. Stop here and keep
        // this city out of the results so a Resume re-scans it.
        if (reviewIssues?.signInBlocked > 0 && job.requireSignIn) {
          stateRec.pending.unshift(city); // not covered: resume must redo it
          job.stoppedReason = 'google_session_expired';
          job.cancelled = true;
          logActivity(
            job,
            `"${category}" · ${stateRec.state} · ${city} — Google asked to sign in, so the saved session is missing or expired. ` +
              'Scan stopped to avoid missing reviews. Sign in to Google again (Excel Scan page, or `npm run maps:login`), then Resume the scan from the Archive.',
            'error'
          );
          return;
        }

        (job.collectedLeadsByState[category][stateRec.state] ??= []).push(...leads);
        stateRec.leadsCollected += leads.length;
        stateRec.businessesProcessed += businessesScraped;
        stateRec.incompleteBusinesses += reviewIssues?.incomplete || 0;
        stateRec.skippedListings += skippedListings || 0;
        stateRec.duplicatesSkipped += duplicatesSkipped || 0;
        // Early brake: pages failing to open is what precedes Google's check.
        if (job.pace?.noteOutcome?.(businessesScraped || 0, skippedListings || 0)) {
          logActivity(
            job,
            `Listings are failing more than usual, so the pace was cut to ${Math.round(job.pace.perMinute)}/min before Google notices. It will climb again if things stay healthy.`,
            'warn'
          );
        }
        stateRec.prefiltered += prefiltered || 0;
        stateRec.covered.push(city);
        noteCityCovered(job, category);
        logActivity(
          job,
          `"${category}" · ${stateRec.state} · ${city} — ${leads.length} lead${leads.length === 1 ? '' : 's'} (${stateRec.covered.length + stateRec.failed.length}/${stateRec.citiesTotal} cities)` +
            (reviewIssues?.incomplete ? ` · ${reviewIssues.incomplete} business${reviewIssues.incomplete === 1 ? '' : 'es'} not fully read` : '') +
            (skippedListings ? ` · ${skippedListings} listing${skippedListings === 1 ? '' : 's'} skipped` : ''),
          reviewIssues?.incomplete || skippedListings ? 'warn' : 'info'
        );
      } catch (err) {
        if (err instanceof GoogleBlockedError || err?.code === 'GOOGLE_BLOCKED') {
          // Not a failed city: Google asked this network to slow down. Put the
          // city back, pause every worker, and wait for it to clear.
          stateRec.pending.unshift(city);
          enterBlockedPause(job, err);
          // Wait out the pause (the watcher lifts it), then carry on with the
          // next city: a worker must survive a block, not end with it.
          await waitWhilePaused(job);
          continue;
        }
        if (job.cancelled) {
          // Interrupted by Cancel: not covered and not failed. Back to pending,
          // so the state is not recorded as done and a Resume redoes the city.
          stateRec.pending.unshift(city);
          return;
        }
        const tried = (stateRec.attempts[city] = (stateRec.attempts[city] || 0) + 1);
        if (tried < CITY_ATTEMPTS && !job.cancelled) {
          stateRec.pending.push(city); // try it again after the others
          logActivity(job, `"${category}" · ${stateRec.state} · ${city} — failed (${err.message}); will retry`, 'warn');
        } else {
          stateRec.failed.push(city);
          logActivity(job, `"${category}" · ${stateRec.state} · ${city} — failed: ${err.message}`, 'warn');
        }
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
  // 'done' only when every city was covered: a state with failed cities is
  // left 'cancelled' (not in `completedStates`), so a Resume re-scans it.
  stateRec.status = stateRec.pending.length === 0 && stateRec.failed.length === 0 ? 'done' : 'cancelled';
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
      scannedAt: job.startedAt,
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
      concurrency: job.concurrency,
      coverage: job.coverage,
      completedCities: completedCitiesFromStates(job.categoryStates[category]),
    });

    archive.status = isFinal ? 'done' : 'partial';
    archive.result = record;
    archive.error = null;

    // A re-scan replaces an older archive — but only now that the new one
    // is complete, so a cancelled or failed re-scan loses nothing.
    if (isFinal && archive.replacesArchiveId) {
      try {
        await deleteExcelArchive(archive.replacesArchiveId);
        logActivity(job, `"${category}" — replaced the earlier scan; old archive deleted.`);
      } catch (err) {
        logActivity(job, `"${category}" — could not delete the earlier scan: ${err.message}`, 'warn');
      }
      archive.replacesArchiveId = null;
    }
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
        await recycleBrowser(job);
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
  const allStates = Object.values(job.categoryStates).flat();
  const notFullyRead = allStates.reduce((n, st) => n + (st.incompleteBusinesses || 0), 0);
  const skipped = allStates.reduce((n, st) => n + (st.skippedListings || 0), 0);
  if (notFullyRead || skipped) {
    logActivity(
      job,
      `Coverage: ${notFullyRead} business${notFullyRead === 1 ? '' : 'es'} could not be proven fully read and ${skipped} listing${skipped === 1 ? '' : 's'} could not be opened. ` +
        'Their reviews may be missing; re-scan to try again.',
      'warn'
    );
  } else if (!job.cancelled) {
    logActivity(job, 'Coverage: every business was read completely (reviews sorted and read back to the date window).');
  }
  const sortSummary = describeSortDiagnostics();
  if (sortSummary) logActivity(job, sortSummary, sortSummary.includes('not sorted') ? 'warn' : 'info');
  logActivity(job, `Scan finished in ${Math.round((job.finishedAt - job.startedAt) / 1000)}s.`);
}

/**
 * @param {object} opts
 * @param {string[]} opts.categories
 * @param {number} [opts.concurrency] - 2-10, default 10. Workers scan cities
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
  // How many places to search: 'standard' (10 largest cities per state),
  // 'extended' (every place of 25,000+) or 'maximum' (5,000+ plus city grids).
  coverage = 'standard',
  resumeArchives,
  // category -> id of an older archive to delete once the new one completes.
  replacesArchiveIds,
  // Refuse to scan (and stop mid-scan) without a signed-in Google session:
  // anonymous visitors cannot sort reviews, so 1-star reviews would be missed.
  requireSignIn = true,
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
  if (!statesOverride && !isCoverageTier(coverage)) {
    const err = new Error(`Unknown coverage "${coverage}". Use standard, extended or maximum.`);
    err.status = 400;
    throw err;
  }
  const states = statesOverride || buildCoverage(coverage);
  if (!states.length) {
    throw new Error('No state/city data available — check usStateCities.js');
  }

  const poolSize = clampConcurrency(concurrency);

  const categoryStates = {};
  const categoryStatus = {};
  const collectedLeadsByState = {};
  const categoryArchives = {};
  const archiveMutexes = {};
  const seedSeen = {};
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
      replacesArchiveId: replacesArchiveIds?.[category] || null,
    };
    archiveMutexes[category] = new Mutex();

    for (const [state, leads] of Object.entries(resume?.seedLeadsByState || {})) {
      collectedLeadsByState[category][state] = leads;
    }
    // Resuming: skip the cities already covered and do not read a business twice.
    if (resume) {
      applyResumeProgress(categoryStates[category], resume.completedCities, resume.seedLeadsByState);
      seedSeen[category] = new Set();
      for (const leads of Object.values(resume.seedLeadsByState || {})) {
        for (const id of placeIdsFromLeads(leads)) seedSeen[category].add(id);
      }
    }
  }

  const thisJob = {
    categories: uniqueCategories,
    concurrency: poolSize,
    dateRange: String(dateRange),
    maxResultsPerCity: Math.max(4, Number(maxResultsPerCity) || DEFAULT_MAX_RESULTS_PER_CITY),
    analyze: Boolean(analyze),
    scrapeLocationFn,
    requireSignIn: Boolean(requireSignIn),
    stoppedReason: null,
    // Set while Google's "unusual traffic" check has the scan paused.
    blocked: null,
    // Place ids already read, per category: a business shared by neighbouring cities is read once.
    seenPlaces: Object.fromEntries(uniqueCategories.map((c) => [c, seedSeen[c] || new Set()])),
    // The tier this scan belongs to. A resume passes the archive's own tier along with
    // the states it still needs, so the archive keeps its label (and a second resume
    // rebuilds the same city list).
    coverage: isCoverageTier(coverage) ? coverage : 'custom',
    // name -> { lat, lng, zoom } for the grid points of large cities, per state.
    citySpecs: Object.fromEntries(states.map((st) => [st.state, st.specs || {}])),
    // Pace shared by all workers; finds the rate Google tolerates (see AdaptivePace).
    pace: null,
    checkpoint: {},
    // Saves a category's progress to its archive (not used when the scraper is injected, i.e. in tests).
    checkpointFn: null,
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
    // Scans no longer write per-lead Firestore documents (their results
    // live in the Excel workbooks); kept at 0 for the status payload.
    firebaseLeadsSaved: 0,
  };

  thisJob.checkpointFn = scrapeLocationFn
    ? null
    : (category) => thisJob.archiveMutexes[category].runExclusive(() => uploadCategoryArchiveNow(thisJob, category, { isFinal: false }));
  currentJob = thisJob;
  resetSortDiagnostics();
  _resetSharedPace();
  thisJob.pace = sharedPace();
  const totalCities = categoryStates[uniqueCategories[0]].reduce((sum, s) => sum + s.citiesTotal, 0);
  logActivity(
    thisJob,
    `Starting scan: ${uniqueCategories.length} categor${uniqueCategories.length === 1 ? 'y' : 'ies'} × ${categoryStates[uniqueCategories[0]].length} states (${totalCities} cities each), ${poolSize} workers.`
  );

  try {
    thisJob.browser = await launchBrowser();
  } catch (err) {
    // Without this, a browser-launch failure (e.g. Playwright browsers not
    // installed) leaves `currentJob` permanently stuck at status 'running'
    // — `runJob` (the only thing that ever reads `cancelled` and flips
    // status to 'done') never even started, so Cancel would set a flag
    // nothing is listening for, and every future scan attempt would keep
    // failing with "a scan is already running" forever until the backend
    // process itself was restarted.
    currentJob = null;
    throw err;
  }

  // A scan that cannot sort reviews would quietly miss most 1-star reviews, so
  // it does not start. (Skipped for the injected scraper used by tests.)
  if (requireSignIn && !scrapeLocationFn) {
    const session = await checkBrowserSignedIn(thisJob.browser).catch(() => ({ status: 'unknown' }));
    if (session.status === 'anonymous' || session.status === 'signed_out') {
      await thisJob.browser.close().catch(() => {});
      currentJob = null;
      const err = new Error(
        session.status === 'anonymous'
          ? 'Sign in to Google first: reviews cannot be sorted without it, so 1-star reviews would be missed. Use "Sign in to Google" on the scan page (or `npm run maps:login`).'
          : 'The saved Google session is signed out or has expired. Sign in again (Sign in to Google on the scan page, or `npm run maps:login`), then start the scan.'
      );
      err.status = 409;
      err.code = 'GOOGLE_SIGN_IN_REQUIRED';
      throw err;
    }
  }
  // Do not start into a Google check: every city would come back empty.
  if (!scrapeLocationFn) {
    const state = await probeGoogleMaps(thisJob.browser).catch(() => 'unknown');
    if (state === 'blocked') {
      await thisJob.browser.close().catch(() => {});
      currentJob = null;
      const err = new Error(
        'Google is showing its "unusual traffic" check for this network right now, so a scan would only collect empty results. ' +
          'Wait (it usually clears within hours) and try again. If it persists, open Google Maps in the scanner browser (`npm run maps:open`) and complete the check yourself.'
      );
      err.status = 409;
      err.code = 'GOOGLE_BLOCKED';
      throw err;
    }
  }
  runJob(thisJob).catch((err) => {
    console.error('State/city scan crashed:', err);
    logActivity(thisJob, `Scan crashed: ${err.message}`, 'error');
  });

  return {
    started: true,
    categories: uniqueCategories,
    concurrency: poolSize,
    totalStates: categoryStates[uniqueCategories[0]].length,
    coverage: thisJob.coverage,
    totalSearches: categoryStates[uniqueCategories[0]].reduce((n, st) => n + st.citiesTotal, 0),
  };
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

  const coverage = isCoverageTier(archive.coverage) ? archive.coverage : 'standard';
  const stateData = allStatesOverride || buildCoverage(coverage);
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
    concurrency: concurrency ?? archive.concurrency,
    dateRange: archive.dateRange || '30',
    maxResultsPerCity: archive.maxResultsPerState || DEFAULT_MAX_RESULTS_PER_CITY,
    analyze: archive.analyze || false,
    scrapeLocationFn,
    statesOverride: stateData.filter((s) => missingStates.includes(s.state)),
    coverage,
    resumeArchives: {
      [category]: {
        id: archive.id,
        fileName: archive.fileName,
        allStates,
        completedStates,
        priorBusinessesProcessed: archive.totalBusinessesProcessed || 0,
        seedLeadsByState,
        completedCities: archive.completedCities || {},
      },
    },
  });

  logActivity(currentJob, `Resuming "${category}" — ${missingStates.length} of ${allStates.length} states remaining.`);
  return result;
}

/**
 * Re-runs a finished scan from scratch — same category and settings, every
 * state — and deletes the old archive (and its no-website companion) only
 * once the new one has completed. Meant for scans old enough that their
 * reviews are stale.
 */
export async function rescanStateCityArchive({ archiveId, concurrency, scrapeLocationFn } = {}) {
  const archive = archiveId ? await getExcelArchive(archiveId) : null;
  const fail = (status, message) => Object.assign(new Error(message), { status });
  if (!archive) throw fail(404, 'Archive not found');
  if (archive.kind === 'no_website') throw fail(400, 'Re-scan the review archive; it also refreshes its no-website file.');
  if (!archive.category) throw fail(400, 'This archive has no category recorded — cannot re-scan.');
  if (archive.status !== 'complete') throw fail(400, 'Only a finished scan can be re-scanned. Resume it instead.');

  const result = await startStateCityScan({
    categories: [archive.category],
    concurrency: concurrency ?? archive.concurrency ?? undefined,
    dateRange: archive.dateRange || '30',
    maxResultsPerCity: archive.maxResultsPerState || DEFAULT_MAX_RESULTS_PER_CITY,
    analyze: archive.analyze || false,
    scrapeLocationFn,
    coverage: isCoverageTier(archive.coverage) ? archive.coverage : 'standard',
    replacesArchiveIds: { [archive.category]: archive.id },
  });
  logActivity(currentJob, `Re-scanning "${archive.category}" — the earlier scan is deleted when this one finishes.`);
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
    const firebaseLeadsSaved = states.reduce((sum, s) => sum + (s.firebaseLeadsSaved || 0), 0);
    const websiteLeadsFound = states.reduce((sum, s) => sum + (s.websiteLeadsFound || 0), 0);
    const incompleteBusinesses = states.reduce((sum, s) => sum + (s.incompleteBusinesses || 0), 0);
    const skippedListings = states.reduce((sum, s) => sum + (s.skippedListings || 0), 0);

    return {
      category,
      status: job.categoryStatus[category],
      statesTotal: states.length,
      statesDone,
      citiesTotal,
      citiesDone,
      leadsCollected,
      businessesProcessed,
      // Always 0 now: scans no longer write per-lead Firestore documents.
      // Kept so the status payload shape does not change.
      firebaseLeadsSaved,
      // Separate lead type entirely (no website found) — never counted
      // in `leadsCollected`/`firebaseLeadsSaved`, which are review leads.
      websiteLeadsFound,
      // Businesses whose reviews could not be proven fully read, and listings
      // that could not be opened: the scan's own account of what it may have missed.
      incompleteBusinesses,
      skippedListings,
      duplicatesSkipped: states.reduce((sum, s) => sum + (s.duplicatesSkipped || 0), 0),
      prefiltered: states.reduce((sum, s) => sum + (s.prefiltered || 0), 0),
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
        firebaseLeadsSaved: s.firebaseLeadsSaved || 0,
        websiteLeadsFound: s.websiteLeadsFound || 0,
        incompleteBusinesses: s.incompleteBusinesses || 0,
        skippedListings: s.skippedListings || 0,
        duplicatesSkipped: s.duplicatesSkipped || 0,
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
    firebaseLeadsSaved: job.firebaseLeadsSaved || 0,
    websiteLeadsFound: categories.reduce((sum, c) => sum + (c.websiteLeadsFound || 0), 0),
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
    paused: job.paused,
    stoppedReason: job.stoppedReason,
    blocked: job.blocked,
    coverage: job.coverage,
    pace: job.pace ? { perMinute: job.pace.perMinute, max: job.pace.max, learnedCap: job.pace.learnedCap ?? null } : null,
    // How each review lookup went (sorted, sign-in required, ...): why some businesses are "not fully read".
    sortStats: getSortDiagnostics(),
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
  if (job.blocked) {
    // Google's check is still up: resuming now would only be blocked again and
    // prolong it. The scan continues by itself once Google serves results.
    logActivity(job, 'Google\'s check is still showing, so the scan stays paused; it resumes by itself once Google serves results.', 'warn');
    return true;
  }
  job.paused = false;
  logActivity(job, 'Scan resumed.');
  return true;
}

/** Exposed for tests only. */
export function _resetStateCityJobForTests() {
  currentJob = null;
}
