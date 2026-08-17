/**
 * Every US state's full city list (user-supplied, see
 * `usStatesCities_fixed.json`) — the data behind the state-by-state,
 * city-by-city scan (`stateCityOrchestrator.js`). Unlike `usStates.js`
 * (one representative metro per state, used by the older nationwide/
 * multi-country flow), this is exhaustive: every incorporated city in the
 * source file, so a state's scan genuinely covers the whole state rather
 * than one dense metro standing in for it.
 */

import raw from './usStatesCities_fixed.json' with { type: 'json' };

// Fallback only — used if a future refresh of the source file drops
// District of Columbia again (earlier versions of it didn't have one).
// The current file does include its own DC entry, so this is normally
// unused; guarded below against double-counting either way.
const DC_FALLBACK_CITIES = ['Washington'];

const STATE_NAMES = Object.keys(raw).filter(
  // "countries": [] is a stray non-state key the source file carries —
  // filtered out here rather than in the source file, so a future refresh
  // of that file doesn't silently reintroduce it.
  (key) => key !== 'countries' && Array.isArray(raw[key]?.cities) && raw[key].cities.length > 0
);

/** @type {{state: string, cities: string[]}[]} */
export const US_STATE_CITIES = [
  ...STATE_NAMES.map((state) => ({ state, cities: raw[state].cities })),
  ...(STATE_NAMES.includes('District of Columbia') ? [] : [{ state: 'District of Columbia', cities: DC_FALLBACK_CITIES }]),
].sort((a, b) => a.state.localeCompare(b.state));

export function totalCityCount() {
  return US_STATE_CITIES.reduce((sum, s) => sum + s.cities.length, 0);
}

export function citiesForState(state) {
  return US_STATE_CITIES.find((s) => s.state === state)?.cities ?? [];
}
