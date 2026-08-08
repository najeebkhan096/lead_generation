/**
 * Registry of countries the nationwide scan can cover. Each entry's
 * `regions` list has the same {state, city} shape as US_STATES, so the
 * existing `locationQuery`/`shuffleStates` helpers in usStates.js work
 * unchanged for every country.
 */

import { US_STATES } from './usStates.js';
import { UK_REGIONS } from './ukRegions.js';
import { GERMANY_STATES } from './germanyStates.js';
import { CANADA_PROVINCES } from './canadaProvinces.js';

export const COUNTRIES = {
  US: {
    code: 'US',
    name: 'United States',
    shortName: 'USA',
    label: 'All 50 U.S. states + D.C.',
    regions: US_STATES,
  },
  UK: {
    code: 'UK',
    name: 'United Kingdom',
    shortName: 'UK',
    label: 'All UK regions',
    regions: UK_REGIONS,
  },
  DE: {
    code: 'DE',
    name: 'Germany',
    shortName: 'Germany',
    label: 'All 16 German states',
    regions: GERMANY_STATES,
  },
  CA: {
    code: 'CA',
    name: 'Canada',
    shortName: 'Canada',
    label: 'All Canadian provinces & territories',
    regions: CANADA_PROVINCES,
  },
};

const DEFAULT_COUNTRY = 'US';

export function countryMeta(country) {
  const key = String(country || DEFAULT_COUNTRY).toUpperCase();
  return COUNTRIES[key] || COUNTRIES[DEFAULT_COUNTRY];
}

export function regionsForCountry(country) {
  return countryMeta(country).regions;
}
