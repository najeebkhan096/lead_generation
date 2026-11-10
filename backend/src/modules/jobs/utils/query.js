/** Helpers for turning a search query into text a source's API understands. */

import { fold } from './text.js';
import { WORLDWIDE_CODE } from '../models/constants.js';

/** "Los Angeles, California, United States" — consecutive repeats removed ("Doha, Doha" -> "Doha"). */
export function locationText(query, { includeCountry = true } = {}) {
  if (query.remoteOnly || query.country?.code === WORLDWIDE_CODE) {
    return query.country?.code === WORLDWIDE_CODE || !includeCountry ? '' : query.country?.name || '';
  }
  const parts = [query.city, query.state, includeCountry ? query.country?.name : null].filter(Boolean);
  return parts.filter((p, i) => i === 0 || fold(p) !== fold(parts[i - 1])).join(', ');
}

/** Title plus the extra keywords, as one search phrase. */
export function searchPhrase(query, { withRemote = false } = {}) {
  const words = [query.title, ...(query.keywords || [])];
  if (withRemote && (query.remoteOnly || query.country?.code === WORLDWIDE_CODE)) words.push('remote');
  return words.filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}
