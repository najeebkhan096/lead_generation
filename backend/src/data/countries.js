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
import { ITALY_REGIONS } from './italyRegions.js';
import { FRANCE_REGIONS } from './franceRegions.js';
import { AUSTRALIA_STATES } from './australiaStates.js';
import { AUSTRIA_STATES } from './austriaStates.js';
import { DENMARK_REGIONS } from './denmarkRegions.js';
import { SPAIN_REGIONS } from './spainRegions.js';
import { NETHERLANDS_PROVINCES } from './netherlandsProvinces.js';
import { BELGIUM_PROVINCES } from './belgiumProvinces.js';
import { SWITZERLAND_CANTONS } from './switzerlandCantons.js';
import { SWEDEN_COUNTIES } from './swedenCounties.js';

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
  IT: {
    code: 'IT',
    name: 'Italy',
    shortName: 'Italy',
    label: 'All 20 Italian regions',
    regions: ITALY_REGIONS,
  },
  FR: {
    code: 'FR',
    name: 'France',
    shortName: 'France',
    label: 'All 13 French regions',
    regions: FRANCE_REGIONS,
  },
  AU: {
    code: 'AU',
    name: 'Australia',
    shortName: 'Australia',
    label: 'All Australian states & territories',
    regions: AUSTRALIA_STATES,
  },
  AT: {
    code: 'AT',
    name: 'Austria',
    shortName: 'Austria',
    label: 'All 9 Austrian states',
    regions: AUSTRIA_STATES,
  },
  DK: {
    code: 'DK',
    name: 'Denmark',
    shortName: 'Denmark',
    label: 'All 5 Danish regions',
    regions: DENMARK_REGIONS,
  },
  ES: {
    code: 'ES',
    name: 'Spain',
    shortName: 'Spain',
    label: 'All 17 Spanish autonomous communities',
    regions: SPAIN_REGIONS,
  },
  NL: {
    code: 'NL',
    name: 'Netherlands',
    shortName: 'Netherlands',
    label: 'All 12 Dutch provinces',
    regions: NETHERLANDS_PROVINCES,
  },
  BE: {
    code: 'BE',
    name: 'Belgium',
    shortName: 'Belgium',
    label: 'All Belgian provinces + Brussels',
    regions: BELGIUM_PROVINCES,
  },
  CH: {
    code: 'CH',
    name: 'Switzerland',
    shortName: 'Switzerland',
    label: 'All 26 Swiss cantons',
    regions: SWITZERLAND_CANTONS,
  },
  SE: {
    code: 'SE',
    name: 'Sweden',
    shortName: 'Sweden',
    label: 'All 21 Swedish counties',
    regions: SWEDEN_COUNTIES,
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
