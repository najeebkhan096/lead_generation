/**
 * Orchestrates search → scrape → filter → memory store.
 */

import * as googleMaps from '../scraper/googleMapsScraper.js';
import * as bing from '../scraper/bingScraper.js';
import * as yelp from '../scraper/yelpScraper.js';
import { filterRecentOneStarLeads } from './reviewFilter.js';
import { enrichLeadWithAnalysis } from './reviewAnalyzer.js';
import {
  setLeads,
  setStatus,
  setProgress,
  setLastSearch,
  getStore,
  clearLeads,
} from '../utils/memoryStore.js';

/**
 * Run a full lead search. Updates in-memory store as it progresses.
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
  setLastSearch({ location, category, dateRange, maxResults, analyze });
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
    let businesses = await googleMaps.searchBusinesses(category, location, {
      maxResults,
      onProgress,
    });

    // Fallbacks if Google returned nothing usable
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

    setProgress({
      message: `Filtering for recent 1-star reviews (${businesses.length} businesses)...`,
      processed: businesses.length,
    });

    let leads = filterRecentOneStarLeads(businesses, { dateRange });

    if (analyze) {
      leads = leads.map(enrichLeadWithAnalysis);
    }

    setLeads(leads);
    setProgress({
      message: `Done. ${leads.length} leads with recent 1-star reviews.`,
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

export function getCurrentLeads() {
  return getStore();
}
