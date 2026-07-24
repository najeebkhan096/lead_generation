/**
 * Orchestrates search → scrape → filter → WhatsApp → memory store.
 * Supports single-location and nationwide (all US states) searches.
 */

import * as googleMaps from '../scraper/googleMapsScraper.js';
import * as bing from '../scraper/bingScraper.js';
import * as yelp from '../scraper/yelpScraper.js';
import { filterRecentOneStarLeads } from './reviewFilter.js';
import { enrichLeadWithAnalysis } from './reviewAnalyzer.js';
import { filterLeadsWithWhatsApp } from './whatsappChecker.js';
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

async function scrapeLocation(category, location, { maxResults, onProgress }) {
  let businesses = await googleMaps.searchBusinesses(category, location, {
    maxResults,
    onProgress,
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

    setProgress({
      message: `Checking WhatsApp on ${leads.length} lead phones...`,
      found: 0,
      processed: businesses.length,
    });

    leads = await filterLeadsWithWhatsApp(leads, {
      onProgress: (message, checked, total) => {
        setProgress({
          message,
          found: getStore().leads.length,
          processed: checked,
          total,
        });
      },
    });

    if (analyze) {
      leads = leads.map(enrichLeadWithAnalysis);
    }

    setLeads(leads);
    setProgress({
      message: `Done. ${leads.length} leads with WhatsApp-available numbers.`,
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

/**
 * Search every US state (dense metro per state) until targetLeadCount
 * WhatsApp-verified 1-star leads are found (default 100).
 */
export async function findLeadsNationwide({
  category,
  dateRange = '30',
  maxResultsPerState = DEFAULT_PER_STATE,
  targetLeadCount = DEFAULT_TARGET_LEADS,
  analyze = false,
}) {
  if (!category?.trim()) {
    throw new Error('category is required');
  }

  const target = Math.max(1, Number(targetLeadCount) || DEFAULT_TARGET_LEADS);
  const perState = Math.max(4, Number(maxResultsPerState) || DEFAULT_PER_STATE);

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
  setProgress({
    message: `Nationwide search: targeting ${target} WhatsApp leads across ${US_STATES.length} states...`,
    found: 0,
    processed: 0,
    statesDone: 0,
    statesTotal: US_STATES.length,
  });

  const states = shuffleStates(US_STATES);
  let businessesScraped = 0;
  let statesDone = 0;

  try {
    for (const entry of states) {
      if (getStore().leads.length >= target) break;

      const location = locationQuery(entry);
      statesDone += 1;

      setProgress({
        message: `State ${statesDone}/${states.length}: ${entry.state} — scraping ${category}...`,
        found: getStore().leads.length,
        processed: businessesScraped,
        statesDone,
        statesTotal: states.length,
      });

      const onProgress = (message) => {
        setProgress({
          message: `[${entry.state}] ${message}`,
          found: getStore().leads.length,
          processed: businessesScraped,
          statesDone,
          statesTotal: states.length,
        });
      };

      let businesses = [];
      try {
        businesses = await scrapeLocation(category, location, {
          maxResults: perState,
          onProgress,
        });
      } catch (err) {
        onProgress(`Skipped ${entry.state}: ${err.message}`);
        continue;
      }

      businessesScraped += businesses.length;

      let leads = filterRecentOneStarLeads(businesses, { dateRange });
      // Tag with state for results clarity
      leads = leads.map((l) => ({
        ...l,
        location: entry.state,
        searchLocation: location,
      }));

      if (!leads.length) {
        setProgress({
          message: `${entry.state}: no recent 1★ leads — continuing (${getStore().leads.length}/${target})`,
          found: getStore().leads.length,
          processed: businessesScraped,
          statesDone,
          statesTotal: states.length,
        });
        continue;
      }

      setProgress({
        message: `${entry.state}: checking WhatsApp on ${leads.length} 1★ lead(s)...`,
        found: getStore().leads.length,
        processed: businessesScraped,
        statesDone,
        statesTotal: states.length,
      });

      const waLeads = await filterLeadsWithWhatsApp(leads, {
        onProgress: (message) => {
          setProgress({
            message: `[${entry.state}] ${message}`,
            found: getStore().leads.length,
            processed: businessesScraped,
            statesDone,
            statesTotal: states.length,
          });
        },
      });

      let enriched = analyze ? waLeads.map(enrichLeadWithAnalysis) : waLeads;

      // Re-id against global list length for uniqueness
      const existing = getStore().leads;
      const existingKeys = new Set(existing.map(leadKey));
      enriched = enriched
        .filter((l) => !existingKeys.has(leadKey(l)))
        .map((l, idx) => ({
          ...l,
          id: `${l.id || 'lead'}-s${statesDone}-${existing.length + idx + 1}`,
        }));

      if (enriched.length) {
        appendLeads(enriched);
      }

      const found = getStore().leads.length;
      setProgress({
        message:
          found >= target
            ? `Target reached: ${found} WhatsApp leads (stopped after ${statesDone} states).`
            : `${entry.state}: +${enriched.length} — total ${found}/${target} WhatsApp leads`,
        found,
        processed: businessesScraped,
        statesDone,
        statesTotal: states.length,
      });
    }

    const leads = dedupeLeads(getStore().leads).slice(0, target);
    setLeads(leads);
    setProgress({
      message: `Done. ${leads.length} WhatsApp leads from ${statesDone} state(s) (target ${target}).`,
      found: leads.length,
      processed: businessesScraped,
      statesDone,
      statesTotal: states.length,
    });

    return {
      leads,
      meta: {
        location: 'All US states',
        category,
        dateRange,
        nationwide: true,
        statesSearched: statesDone,
        businessesScraped,
        leadsFound: leads.length,
        targetLeadCount: target,
      },
    };
  } catch (err) {
    setStatus('error', err.message);
    setProgress({ message: `Error: ${err.message}` });
    throw err;
  }
}

export function getCurrentLeads() {
  return getStore();
}
