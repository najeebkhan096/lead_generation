/**
 * Orchestrates search → scrape → filter → memory store.
 * Supports single-location and nationwide (all US states) searches.
 */

import * as googleMaps from '../scraper/googleMapsScraper.js';
import * as bing from '../scraper/bingScraper.js';
import * as yelp from '../scraper/yelpScraper.js';
import { filterRecentOneStarLeads } from './reviewFilter.js';
import { enrichLeadWithAnalysis } from './reviewAnalyzer.js';
import { normalizeUsPhone, waMeLink } from './whatsappChecker.js';
import * as whatsappWebService from './whatsappWebService.js';
import * as whatsappSafety from './whatsappSafety.js';
import { US_STATES, locationQuery, shuffleStates } from '../data/usStates.js';
import {
  setLeads,
  appendLeads,
  setStatus,
  setProgress,
  setLastSearch,
  getStore,
  clearLeads,
} from '../utils/memoryStore.js';

const DEFAULT_TARGET_LEADS = 100;
const DEFAULT_PER_STATE = 16;

function leadKey(lead) {
  const maps = (lead.mapsUrl || '').split('?')[0].toLowerCase();
  if (maps) return `maps:${maps}`;
  const phone = String(lead.phone || '').replace(/\D/g, '');
  if (phone) return `phone:${phone}`;
  return `name:${String(lead.business || '').toLowerCase()}|${String(lead.address || '').toLowerCase()}`;
}

function dedupeLeads(leads) {
  const seen = new Set();
  const out = [];
  for (const lead of leads) {
    const key = leadKey(lead);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(lead);
  }
  return out;
}

/** Normalize phone + build wa.me link. WhatsApp is NOT verified — user checks manually. */
function enrichLeadContacts(leads) {
  return leads.map((lead) => {
    const e164 = normalizeUsPhone(lead.phone);
    return {
      ...lead,
      phone: e164 ? `+${e164}` : lead.phone || null,
      waLink: waMeLink(e164),
      hasWhatsApp: false,
    };
  });
}

/**
 * Checks each lead's phone against the live WhatsApp Web session the moment
 * it's found, mutating `hasWhatsApp`/`whatsAppCheckedAt` in place — a no-op
 * if WhatsApp Web isn't connected, so scanning behaves exactly as before
 * for anyone who hasn't linked it. Goes through the same safety-guarded
 * choke point (`whatsappSafety.guardedCheck`) as the bulk validation job,
 * so inline checks during a nationwide multi-category scan and any
 * concurrently-running bulk job share one pacing budget instead of each
 * hammering the session independently.
 */
async function inlineValidateWhatsApp(leads, { shouldStop, checkFn = whatsappSafety.guardedCheck } = {}) {
  const usingRealChecker = checkFn === whatsappSafety.guardedCheck;
  if (usingRealChecker && !whatsappWebService.isReady()) return;

  for (const lead of leads) {
    if (shouldStop?.()) break;
    if (!lead.phone) continue;
    try {
      const result = await checkFn(lead.phone);
      if (result.skipped) break; // cap/circuit hit — rest would skip too
      if (result.checked) {
        lead.hasWhatsApp = result.valid;
        lead.whatsAppCheckedAt = new Date().toISOString();
      }
    } catch {
      // best-effort — leave the lead's WhatsApp fields as "unchecked"
    }
  }
}

async function scrapeLocation(category, location, { maxResults, onProgress, browser } = {}) {
  let businesses = await googleMaps.searchBusinesses(category, location, {
    maxResults,
    onProgress,
    browser,
  });

  if (!businesses.length) {
    businesses = await bing.searchBusinesses(category, location, {
      maxResults,
      onProgress,
    });
  }

  if (!businesses.length) {
    businesses = await yelp.searchBusinesses(category, location, {
      maxResults,
      onProgress,
    });
  }

  return businesses;
}

/**
 * Single-location search (legacy / optional).
 */
export async function findLeads({
  location,
  category,
  dateRange = '30',
  maxResults = 12,
  analyze = false,
}) {
  if (!location?.trim() || !category?.trim()) {
    throw new Error('location and category are required');
  }

  clearLeads();
  setStatus('searching');
  setLastSearch({ location, category, dateRange, maxResults, analyze, nationwide: false });
  setProgress({ message: 'Starting search...', found: 0, processed: 0 });

  const onProgress = (message) => {
    const store = getStore();
    setProgress({
      message,
      found: store.leads.length,
      processed: store.progress.processed,
    });
  };

  try {
    const businesses = await scrapeLocation(category, location, {
      maxResults,
      onProgress,
    });

    setProgress({
      message: `Filtering for recent 1-star reviews (${businesses.length} businesses)...`,
      processed: businesses.length,
    });

    let leads = filterRecentOneStarLeads(businesses, { dateRange });
    leads = enrichLeadContacts(leads);

    if (analyze) {
      leads = leads.map(enrichLeadWithAnalysis);
    }

    setLeads(leads);
    setProgress({
      message: `Done. ${leads.length} businesses with recent 1-star reviews.`,
      found: leads.length,
      processed: businesses.length,
    });

    return {
      leads,
      meta: {
        location,
        category,
        dateRange,
        businessesScraped: businesses.length,
        leadsFound: leads.length,
      },
    };
  } catch (err) {
    setStatus('error', err.message);
    setProgress({ message: `Error: ${err.message}` });
    throw err;
  }
}

import { saveLeadsToFirebase, checkIfCategorySearched } from './firebaseLeadStore.js';

/**
 * Search multiple categories sequentially across all US states.
 *
 * Kept for backward compatibility — the admin console's "New Search" form
 * now uses the concurrent worker-pool path in `multiCategoryOrchestrator.js`
 * for multi-category runs, which is dramatically faster. This still works
 * exactly as before for anything that calls it directly.
 */
export async function findLeadsSequential({
  categories = [],
  dateRange = '30',
  maxResultsPerState = DEFAULT_PER_STATE,
  analyze = false,
}) {
  if (!Array.isArray(categories) || !categories.length) {
    throw new Error('categories array is required');
  }

  setStatus('searching');
  setLastSearch({
    location: 'All US states',
    categories,
    dateRange,
    nationwide: true,
    sequential: true,
  });

  try {
    for (let i = 0; i < categories.length; i++) {
      const category = categories[i];

      // Check if we already searched this category recently
      const alreadySearched = await checkIfCategorySearched(category);
      if (alreadySearched) {
        setProgress({
          message: `Sequential search: skipping "${category}" (already searched in the last 7 days).`,
          found: 0,
          processed: 0,
          statesDone: US_STATES.length,
          statesTotal: US_STATES.length,
        });
        // Short pause to let user see the message
        await new Promise(r => setTimeout(r, 2000));
        continue;
      }

      // Keep searching status active throughout the sequence
      setStatus('searching');

      setProgress({
        message: `Sequential search: starting category ${i + 1}/${categories.length} — "${category}"...`,
        found: 0,
        processed: 0,
        statesDone: 0,
        statesTotal: US_STATES.length,
      });

      // Clear previous category results from memory before starting new one
      clearLeads();

      await findLeadsNationwide({
        category,
        dateRange,
        maxResultsPerState,
        analyze,
        autoSave: true, // Handle separate storage
        skipInitialClear: true, // Don't clear what we just set up
        isSequential: true, // Don't set status to 'done' inside
      });
    }

    setStatus('done');
    setProgress({ message: `Sequential search finished for ${categories.length} categories. Results saved to Firebase.` });
  } catch (err) {
    console.error('Sequential search error:', err);
    setStatus('error', err.message);
    setProgress({ message: `Error: ${err.message}` });
    throw err;
  }
}

/**
 * Core nationwide-per-category scan, isolated from the global in-memory
 * store (`memoryStore.js`) so it's safe to run several of these
 * concurrently — one per worker in the multi-category pool
 * (`multiCategoryOrchestrator.js`). All the actual scraping/filtering/
 * enrichment calls are identical to what `findLeadsNationwide` always
 * did; only the bookkeeping (where progress and results get written) is
 * different. `findLeadsNationwide` below is now a thin adapter that pipes
 * this into the legacy global store, so every existing caller keeps its
 * exact current behavior and output.
 *
 * @param {string} category
 * @param {object} [opts]
 * @param {string} [opts.dateRange]
 * @param {number} [opts.maxResultsPerState]
 * @param {number} [opts.targetLeadCount]
 * @param {boolean} [opts.analyze]
 * @param {import('playwright').Browser} [opts.browser] - shared browser to
 *   scrape with instead of launching a fresh one (each state still gets
 *   its own isolated `BrowserContext` — see googleMapsScraper.js).
 * @param {boolean} [opts.stopAtTarget] - stop once `targetLeadCount` leads
 *   have been found instead of scanning every state. Defaults to false so
 *   `findLeadsNationwide`'s existing exhaustive-scan behavior is
 *   byte-for-byte unchanged; the multi-category pool opts in with `true`.
 * @param {(evt: object) => void} [opts.onProgress] - structured events:
 *   `state-start` { state, statesDone, statesTotal }
 *   `scraper-message` { state, message } - raw messages from the scraper
 *   `businesses-scraped` { delta, total }
 *   `leads-found` { newLeads, total } - newLeads is the actual lead objects,
 *     so callers can mirror them into their own store incrementally. If
 *     WhatsApp Web is connected, each of these leads has already been
 *     checked (`hasWhatsApp`/`whatsAppCheckedAt` set) before this fires —
 *     see `inlineValidateWhatsApp`.
 *   `state-error` { state, message }
 *   `state-done` { state, statesDone, statesTotal, leadsInState }
 * @param {() => boolean} [opts.shouldStop] - checked between states; a
 *   `true` return ends the scan early (e.g. user cancelled this category).
 * @param {() => Promise<void>} [opts.waitWhilePaused] - awaited between
 *   states so a paused category truly does nothing until resumed.
 */
export async function scrapeCategoryNationwide(category, {
  dateRange = '30',
  maxResultsPerState = DEFAULT_PER_STATE,
  targetLeadCount = DEFAULT_TARGET_LEADS,
  analyze = false,
  browser,
  stopAtTarget = false,
  onProgress,
  shouldStop,
  waitWhilePaused,
  // Test-only seam: lets tests inject a fake scraper instead of hitting
  // real Google Maps. Defaults to the real implementation, so production
  // behavior is unaffected.
  scrapeLocationFn = scrapeLocation,
  // Test-only seam: lets tests inject a fake WhatsApp checker instead of
  // hitting the real guarded session. Defaults to the real implementation.
  checkWhatsAppFn = whatsappSafety.guardedCheck,
} = {}) {
  if (!category?.trim()) {
    throw new Error('category is required');
  }

  const target = Math.max(1, Number(targetLeadCount) || DEFAULT_TARGET_LEADS);
  const perState = Math.max(4, Number(maxResultsPerState) || DEFAULT_PER_STATE);
  const states = shuffleStates(US_STATES);

  let businessesScraped = 0;
  let statesDone = 0;
  let leads = [];
  let stoppedEarly = false;
  let stoppedReason = null;

  for (const entry of states) {
    if (waitWhilePaused) await waitWhilePaused();
    if (shouldStop?.()) {
      stoppedEarly = true;
      stoppedReason = 'cancelled';
      break;
    }
    if (stopAtTarget && leads.length >= target) {
      stoppedEarly = true;
      stoppedReason = 'target-reached';
      break;
    }

    const location = locationQuery(entry);
    statesDone += 1;

    onProgress?.({
      type: 'state-start',
      state: entry.state,
      statesDone,
      statesTotal: states.length,
    });

    const onScraperMessage = (message) => {
      onProgress?.({ type: 'scraper-message', state: entry.state, message });
    };

    let businesses = [];
    try {
      businesses = await scrapeLocationFn(category, location, {
        maxResults: perState,
        onProgress: onScraperMessage,
        browser,
      });
    } catch (err) {
      onProgress?.({
        type: 'state-error',
        state: entry.state,
        message: `Skipped ${entry.state}: ${err.message}`,
      });
      onProgress?.({
        type: 'state-done',
        state: entry.state,
        statesDone,
        statesTotal: states.length,
        leadsInState: 0,
      });
      continue;
    }

    businessesScraped += businesses.length;
    onProgress?.({ type: 'businesses-scraped', delta: businesses.length, total: businessesScraped });

    let stateLeads = filterRecentOneStarLeads(businesses, { dateRange });
    stateLeads = enrichLeadContacts(stateLeads);
    stateLeads = stateLeads.map((l) => ({
      ...l,
      location: entry.state,
      searchLocation: location,
    }));

    if (stateLeads.length) {
      const enrichedBase = analyze ? stateLeads.map(enrichLeadWithAnalysis) : stateLeads;

      const existingKeys = new Set(leads.map(leadKey));
      const enriched = enrichedBase
        .filter((l) => !existingKeys.has(leadKey(l)))
        .map((l, idx) => ({
          ...l,
          id: `${l.id || 'lead'}-s${statesDone}-${leads.length + idx + 1}`,
        }));

      if (enriched.length) {
        // Check each new lead's WhatsApp number right as it's found, before
        // moving on to the next — same guarded/paced checker the bulk
        // validation job uses, so this only runs (and only slows things
        // down) when WhatsApp Web is actually connected.
        await inlineValidateWhatsApp(enriched, { shouldStop, checkFn: checkWhatsAppFn });

        leads = [...leads, ...enriched];
        onProgress?.({ type: 'leads-found', newLeads: enriched, total: leads.length });
      }
    }

    onProgress?.({
      type: 'state-done',
      state: entry.state,
      statesDone,
      statesTotal: states.length,
      leadsInState: stateLeads.length,
    });
  }

  leads = dedupeLeads(leads);

  return {
    leads,
    meta: {
      location: 'All US states',
      category,
      dateRange,
      nationwide: true,
      statesSearched: statesDone,
      statesTotal: states.length,
      businessesScraped,
      leadsFound: leads.length,
      stoppedEarly,
      stoppedReason,
    },
  };
}

/**
 * Search every US state (dense metro per state) until exhaustive.
 *
 * Thin adapter around `scrapeCategoryNationwide` that pipes its progress
 * into the legacy global in-memory store — preserves this function's
 * exact existing behavior/output for the single-category and legacy
 * sequential-search callers.
 */
export async function findLeadsNationwide({
  category,
  dateRange = '30',
  maxResultsPerState = DEFAULT_PER_STATE,
  targetLeadCount = DEFAULT_TARGET_LEADS,
  analyze = false,
  autoSave = false,
  skipInitialClear = false,
  isSequential = false,
  // Test-only seam, forwarded to scrapeCategoryNationwide — see there.
  scrapeLocationFn,
}) {
  if (!category?.trim()) {
    throw new Error('category is required');
  }

  const target = Math.max(1, Number(targetLeadCount) || DEFAULT_TARGET_LEADS);
  const perState = Math.max(4, Number(maxResultsPerState) || DEFAULT_PER_STATE);

  if (!skipInitialClear) {
    clearLeads();
    setStatus('searching');
    setLastSearch({
      location: 'All US states',
      category,
      dateRange,
      maxResultsPerState: perState,
      targetLeadCount: target,
      analyze,
      nationwide: true,
    });
  }

  setProgress({
    message: `Nationwide search: scanning "${category}" across ${US_STATES.length} states...`,
    found: 0,
    processed: 0,
    statesDone: 0,
    statesTotal: US_STATES.length,
  });

  let businessesScraped = 0;

  try {
    const { leads, meta } = await scrapeCategoryNationwide(category, {
      dateRange,
      maxResultsPerState: perState,
      targetLeadCount: target,
      analyze,
      stopAtTarget: false, // preserves this function's exact existing exhaustive-scan behavior
      scrapeLocationFn,
      onProgress: (evt) => {
        switch (evt.type) {
          case 'state-start':
            setProgress({
              message: `[${evt.state}] Scanning ${category}... (${evt.statesDone}/${evt.statesTotal} states)`,
              found: getStore().leads.length,
              processed: businessesScraped,
              statesDone: evt.statesDone,
              statesTotal: evt.statesTotal,
            });
            break;
          case 'scraper-message': {
            const scanMatch = evt.message.match(/\[(\d+)\/(\d+)\]/);
            const currentScannedInState = scanMatch ? parseInt(scanMatch[1], 10) : 0;
            setProgress({
              message: `[${evt.state}] ${evt.message}`,
              found: getStore().leads.length,
              processed: businessesScraped + currentScannedInState,
            });
            break;
          }
          case 'businesses-scraped':
            businessesScraped = evt.total;
            break;
          case 'state-error':
            setProgress({
              message: `[${evt.state}] ${evt.message}`,
              found: getStore().leads.length,
              processed: businessesScraped,
            });
            break;
          case 'leads-found':
            appendLeads(evt.newLeads);
            break;
          // 'state-done' has no equivalent progress message in the original
          // single-category flow — intentionally not translated here.
        }
      },
    });

    setLeads(leads, { done: !isSequential });

    if (autoSave) {
      try {
        await saveLeadsToFirebase(leads);
      } catch (saveErr) {
        console.error(`Auto-save failed for ${category}:`, saveErr);
      }
    }

    setProgress({
      message: `Finished "${category}". Found ${leads.length} leads.`,
      found: leads.length,
      processed: businessesScraped,
      statesDone: meta.statesSearched,
      statesTotal: meta.statesTotal,
    });

    return { leads, meta };
  } catch (err) {
    setStatus('error', err.message);
    setProgress({ message: `Error: ${err.message}` });
    throw err;
  }
}

export function getCurrentLeads() {
  return getStore();
}
