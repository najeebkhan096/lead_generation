/**
 * Orchestrates search → scrape → filter → memory store.
 * Supports single-location and nationwide (all US states) searches.
 */

import * as googleMaps from '../../scraper/googleMapsScraper.js';
import * as bing from '../../scraper/bingScraper.js';
import * as yelp from '../../scraper/yelpScraper.js';
import { filterRecentOneStarLeads } from './reviewFilter.js';
import { enrichLeadWithAnalysis } from './reviewAnalyzer.js';
import { normalizePhone, waMeLink } from '../validation/whatsapp/whatsappChecker.js';
import { locationQuery, shuffleStates } from '../../data/usStates.js';
import { countryMeta, regionsForCountry } from '../../data/countries.js';
import {
  setLeads,
  appendLeads,
  setStatus,
  setProgress,
  setLastSearch,
  getStore,
  clearLeads,
  clearLeadsArray,
} from '../../lib/memoryStore.js';

const DEFAULT_TARGET_LEADS = 100;
// Raised from 16: the old cap meant most of the 1-star-review pool per city
// was never even looked at. Scanning more per city costs more time per
// region but finds far more of the qualifying leads that actually exist
// there — 150 covers essentially all of a metro's listings for most
// categories, short of the biggest cities.
const DEFAULT_PER_STATE = 150;

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

/**
 * Normalize phone + build the wa.me link. Nothing here (or anywhere in the
 * scan) checks WhatsApp: `waLink` is only a click-to-chat link, never proof
 * that the number is registered, and `hasWhatsApp` stays false until the
 * user runs WhatsApp validation from the Leads page.
 */
function enrichLeadContacts(leads, country = 'US') {
  return leads.map((lead) => {
    const e164 = normalizePhone(lead.phone, country);
    return {
      ...lead,
      phone: e164 ? `+${e164}` : lead.phone || null,
      waLink: waMeLink(e164),
      hasWhatsApp: false,
    };
  });
}

/**
 * Same phone normalization as `enrichLeadContacts`, minus the WhatsApp
 * fields — website leads are a completely different signal ("no website")
 * from review leads ("bad recent review"), and WhatsApp outreach/validation
 * isn't part of that flow at all, so they never get a `waLink` or
 * `hasWhatsApp` in the first place instead of carrying always-unchecked
 * WhatsApp fields that look like they belong to the review-lead pipeline.
 */
function normalizeLeadPhone(leads, country = 'US') {
  return leads.map((lead) => {
    const e164 = normalizePhone(lead.phone, country);
    return { ...lead, phone: e164 ? `+${e164}` : lead.phone || null };
  });
}

/**
 * How well a batch's reviews were read, from each business's `reviewAccess`
 * (see googleMapsScraper.js): `incomplete` businesses could not be proven
 * fully read, `signInBlocked` of them because Google asked to sign in. A
 * business without a record (another scraper supplied it) is not counted.
 */
export function summarizeReviewAccess(businesses) {
  let incomplete = 0;
  let signInBlocked = 0;
  for (const b of businesses || []) {
    const access = b.reviewAccess;
    if (!access || access.complete) continue;
    incomplete += 1;
    if (access.status === 'signin_required') signInBlocked += 1;
  }
  return { incomplete, signInBlocked };
}

/**
 * Fires `onLeadReady` for each lead the moment it's filtered — callers use
 * this to persist to Firestore one business at a time instead of waiting
 * for the whole city/state to finish. WhatsApp is deliberately not checked
 * here; that lives on the Excel Archive page so scans stay fast.
 */
async function persistReadyLeads(leads, { shouldStop, onLeadReady } = {}) {
  for (const lead of leads) {
    if (shouldStop?.()) break;
    // Callers are responsible for catching their own errors (as
    // `captureWebsiteLeads` does for the website-lead path) so a
    // persistence failure for one lead never stops the rest of the batch.
    await onLeadReady?.(lead);
  }
}

async function scrapeLocation(category, location, { maxResults, onProgress, browser, country, shouldStop, dateRange, seenPlaceIds, googleOnly = false, center } = {}) {
  let businesses = await googleMaps.searchBusinesses(category, location, {
    maxResults,
    onProgress,
    browser,
    country,
    shouldStop,
    dateRange,
    seenPlaceIds,
    center,
  });

  // The review scan needs Google's own data: Bing and Yelp results carry no
  // reviews, and falling back to them turned a blocked search into a city
  // that looked scanned but held one review-less business.
  if (googleOnly) return businesses;

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
      dateRange,
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

import { saveLeadsToFirebase, checkIfCategorySearched } from '../leads/firebaseLeadStore.js';

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
  country = 'US',
}) {
  if (!Array.isArray(categories) || !categories.length) {
    throw new Error('categories array is required');
  }

  const meta = countryMeta(country);
  const regionsTotal = meta.regions.length;

  setStatus('searching');
  setLastSearch({
    location: meta.label,
    country: meta.code,
    categories,
    dateRange,
    nationwide: true,
    sequential: true,
  });

  try {
    for (let i = 0; i < categories.length; i++) {
      const category = categories[i];

      // Check if we already searched this category recently
      const alreadySearched = await checkIfCategorySearched(category, country);
      if (alreadySearched) {
        setProgress({
          message: `Sequential search: skipping "${category}" (already searched in the last 7 days).`,
          found: 0,
          processed: 0,
          statesDone: regionsTotal,
          statesTotal: regionsTotal,
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
        statesTotal: regionsTotal,
      });

      // Clear previous category's leads only — status/lastSearch/progress
      // were just set above for this category and must survive (clearLeads()
      // would silently revert status to 'idle' for the rest of the scan).
      clearLeadsArray();

      await findLeadsNationwide({
        category,
        dateRange,
        maxResultsPerState,
        analyze,
        country,
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
 *     so callers can mirror them into their own store incrementally.
 *   `state-error` { state, message }
 *   `state-done` { state, statesDone, statesTotal, leadsInState }
 * @param {() => boolean} [opts.shouldStop] - checked between states; a
 *   `true` return ends the scan early (e.g. user cancelled this category).
 * @param {() => Promise<void>} [opts.waitWhilePaused] - awaited between
 *   states so a paused category truly does nothing until resumed.
 * @param {(lead: object) => Promise<void>} [opts.onLeadReady] - awaited once
 *   per lead before moving on to the next one — callers use this to persist
 *   a lead immediately instead of waiting for the whole state/category to
 *   finish. WhatsApp is not checked during the scan.
 */
export async function scrapeCategoryNationwide(category, {
  dateRange = '30',
  maxResultsPerState = DEFAULT_PER_STATE,
  targetLeadCount = DEFAULT_TARGET_LEADS,
  analyze = false,
  country = 'US',
  browser,
  stopAtTarget = false,
  onProgress,
  shouldStop,
  waitWhilePaused,
  // Test-only seam: lets tests inject a fake scraper instead of hitting
  // real Google Maps. Defaults to the real implementation, so production
  // behavior is unaffected.
  scrapeLocationFn = scrapeLocation,
  onLeadReady,
} = {}) {
  if (!category?.trim()) {
    throw new Error('category is required');
  }

  const target = Math.max(1, Number(targetLeadCount) || DEFAULT_TARGET_LEADS);
  const perState = Math.max(4, Number(maxResultsPerState) || DEFAULT_PER_STATE);
  const states = shuffleStates(regionsForCountry(country));

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
        country,
        shouldStop,
        dateRange,
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
    stateLeads = enrichLeadContacts(stateLeads, country);
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
        await persistReadyLeads(enriched, { shouldStop, onLeadReady });

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
      location: countryMeta(country).label,
      country: countryMeta(country).code,
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

let _citySeq = 0;

/**
 * Scrapes ONE city and returns its filtered/enriched leads — the same
 * per-location pipeline `scrapeCategoryNationwide` runs once per state,
 * extracted to run against a single (city, state) pair instead of looping
 * through every location itself. Used by `stateCityOrchestrator.js`'s
 * per-city worker pool, where the caller owns sequencing (which state,
 * which cities, in what order, how many at once) and just wants one
 * location scraped end-to-end.
 *
 * Returns `{ leads, businessesScraped, reviewIssues, skippedListings, ... }`:
 * `leads` are the 1-star-review leads inside `dateRange`; `reviewIssues`
 * says how many businesses' reviews could NOT be proven fully read (and how
 * many of those were blocked by Google's sign-in prompt), and
 * `skippedListings` how many listings could not be opened at all, so the
 * caller never presents a partly-read city as fully covered. Businesses with
 * no website are no longer scanned for; `websiteLeads` stays empty.
 */
export async function scrapeOneCity(category, { city, state, center }, {
  dateRange = '30',
  maxResults = DEFAULT_PER_STATE,
  analyze = false,
  country = 'US',
  browser,
  onProgress,
  shouldStop,
  scrapeLocationFn = scrapeLocation,
  // Place ids already read in this scan, so a business listed by several
  // neighbouring cities is read once.
  seenPlaceIds,
  // Called one business at a time — the state-city orchestrator uses this
  // to save each lead to Firestore immediately instead of waiting for the
  // whole city (or category) to finish. WhatsApp is not checked here.
  onLeadReady,
  // Accepted for older callers; no-website leads are no longer scanned for.
  persistWebsiteLeads = true, // eslint-disable-line no-unused-vars
} = {}) {
  // A grid point of a large city is searched around its coordinates; the name is only a label.
  const location = locationQuery({ city: center?.within || city, state });

  const businesses = await scrapeLocationFn(category, location, {
    maxResults,
    onProgress,
    browser,
    country,
    shouldStop,
    dateRange,
    seenPlaceIds,
    googleOnly: true,
    center,
  });

  // No result list at all is NOT an empty city: Google did not answer with
  // results (a layout change, a slow page). Failing here gets the city retried
  // and, if it keeps happening, recorded as failed, instead of "0 leads, done".
  if (businesses.searchStatus === 'feed_missing') {
    throw new Error(`Google returned no result list for ${location}`);
  }

  const reviewIssues = summarizeReviewAccess(businesses);
  let leads = filterRecentOneStarLeads(businesses, { dateRange });
  leads = enrichLeadContacts(leads, country);
  leads = leads.map((l) => ({ ...l, location: state, searchLocation: location }));
  if (analyze) leads = leads.map(enrichLeadWithAnalysis);

  leads = dedupeLeads(leads).map((l) => ({ ...l, id: `${l.id || 'lead'}-c${(_citySeq += 1)}` }));

  if (leads.length) {
    await persistReadyLeads(leads, { shouldStop, onLeadReady });
  }

  return {
    leads,
    businessesScraped: businesses.length,
    reviewIssues,
    skippedListings: businesses.skippedListings || 0,
    duplicatesSkipped: businesses.duplicatesSkipped || 0,
    prefiltered: businesses.prefiltered || 0,
    listingsFound: businesses.listingsFound || 0,
    websiteLeadsFound: 0,
    websiteLeads: [],
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
  country = 'US',
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
  const meta = countryMeta(country);

  if (!skipInitialClear) {
    clearLeads();
    setStatus('searching');
    setLastSearch({
      location: meta.label,
      country: meta.code,
      category,
      dateRange,
      maxResultsPerState: perState,
      targetLeadCount: target,
      analyze,
      nationwide: true,
    });
  }

  setProgress({
    message: `Nationwide search: scanning "${category}" across ${meta.regions.length} ${meta.name} regions...`,
    found: 0,
    processed: 0,
    statesDone: 0,
    statesTotal: meta.regions.length,
  });

  let businessesScraped = 0;

  try {
    const { leads, meta: resultMeta } = await scrapeCategoryNationwide(category, {
      dateRange,
      maxResultsPerState: perState,
      targetLeadCount: target,
      analyze,
      country,
      stopAtTarget: false, // preserves this function's exact existing exhaustive-scan behavior
      scrapeLocationFn,
      onProgress: (evt) => {
        switch (evt.type) {
          case 'state-start':
            setProgress({
              message: `[${evt.state}] Scanning ${category}... (${evt.statesDone}/${evt.statesTotal} states)`,
              state: evt.state,
              found: getStore().leads.length,
              processed: businessesScraped,
              statesDone: evt.statesDone - 1, // this state isn't done yet — matches multiCategoryOrchestrator.js
              statesTotal: evt.statesTotal,
            });
            break;
          case 'scraper-message': {
            // "Opening listing X/Y" fires on every listing attempted (success
            // or not) — the only reliable live signal for how far into this
            // region's listing pool the scan actually is. The old regex only
            // matched the bracketed "Collected: ... [x/y]" message (which
            // fires far less often), so `processed` sat frozen near 0 for
            // most of a region's scan and never reflected real progress.
            const openingMatch = evt.message.match(/^Opening listing (\d+)\/(\d+)/);
            const progressUpdate = {
              message: `[${evt.state}] ${evt.message}`,
              state: evt.state,
              found: getStore().leads.length,
            };
            if (openingMatch) {
              progressUpdate.processed = businessesScraped + parseInt(openingMatch[1], 10);
            }
            setProgress(progressUpdate);
            break;
          }
          case 'businesses-scraped':
            businessesScraped = evt.total;
            break;
          case 'state-error':
            setProgress({
              message: `[${evt.state}] ${evt.message}`,
              state: evt.state,
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
      statesDone: resultMeta.statesSearched,
      statesTotal: resultMeta.statesTotal,
    });

    return { leads, meta: resultMeta };
  } catch (err) {
    setStatus('error', err.message);
    setProgress({ message: `Error: ${err.message}` });
    throw err;
  }
}

export function getCurrentLeads() {
  return getStore();
}
