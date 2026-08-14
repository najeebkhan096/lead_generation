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
import { IRELAND_REGIONS } from './irelandRegions.js';
import { NORWAY_COUNTIES } from './norwayCounties.js';
import { FINLAND_REGIONS } from './finlandRegions.js';
import { PORTUGAL_DISTRICTS } from './portugalDistricts.js';
import { POLAND_VOIVODESHIPS } from './polandVoivodeships.js';
import { CZECH_REGIONS } from './czechRegions.js';
import { HUNGARY_COUNTIES } from './hungaryCounties.js';
import { MEXICO_STATES } from './mexicoStates.js';
import { SAUDI_PROVINCES } from './saudiProvinces.js';
import { UAE_EMIRATES } from './uaeEmirates.js';
import { QATAR_MUNICIPALITIES } from './qatarMunicipalities.js';
import { KUWAIT_GOVERNORATES } from './kuwaitGovernorates.js';
import { BAHRAIN_GOVERNORATES } from './bahrainGovernorates.js';
import { OMAN_GOVERNORATES } from './omanGovernorates.js';

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
  IE: {
    code: 'IE',
    name: 'Ireland',
    shortName: 'Ireland',
    label: 'All 4 Irish provinces',
    regions: IRELAND_REGIONS,
  },
  NO: {
    code: 'NO',
    name: 'Norway',
    shortName: 'Norway',
    label: 'All 11 Norwegian counties',
    regions: NORWAY_COUNTIES,
  },
  FI: {
    code: 'FI',
    name: 'Finland',
    shortName: 'Finland',
    label: 'Major Finnish regions',
    regions: FINLAND_REGIONS,
  },
  PT: {
    code: 'PT',
    name: 'Portugal',
    shortName: 'Portugal',
    label: 'All Portuguese districts & autonomous regions',
    regions: PORTUGAL_DISTRICTS,
  },
  PL: {
    code: 'PL',
    name: 'Poland',
    shortName: 'Poland',
    label: 'All 16 Polish voivodeships',
    regions: POLAND_VOIVODESHIPS,
  },
  CZ: {
    code: 'CZ',
    name: 'Czech Republic',
    shortName: 'Czech Republic',
    label: 'All 14 Czech regions',
    regions: CZECH_REGIONS,
  },
  HU: {
    code: 'HU',
    name: 'Hungary',
    shortName: 'Hungary',
    label: 'All 19 counties + Budapest',
    regions: HUNGARY_COUNTIES,
  },
  MX: {
    code: 'MX',
    name: 'Mexico',
    shortName: 'Mexico',
    label: 'All 31 states + Mexico City',
    regions: MEXICO_STATES,
  },
  SA: {
    code: 'SA',
    name: 'Saudi Arabia',
    shortName: 'Saudi Arabia',
    label: 'All 13 Saudi provinces',
    regions: SAUDI_PROVINCES,
  },
  AE: {
    code: 'AE',
    name: 'United Arab Emirates',
    shortName: 'UAE',
    label: 'All 7 Emirates',
    regions: UAE_EMIRATES,
  },
  QA: {
    code: 'QA',
    name: 'Qatar',
    shortName: 'Qatar',
    label: 'All 8 municipalities',
    regions: QATAR_MUNICIPALITIES,
  },
  KW: {
    code: 'KW',
    name: 'Kuwait',
    shortName: 'Kuwait',
    label: 'All 6 governorates',
    regions: KUWAIT_GOVERNORATES,
  },
  BH: {
    code: 'BH',
    name: 'Bahrain',
    shortName: 'Bahrain',
    label: 'All 4 governorates',
    regions: BAHRAIN_GOVERNORATES,
  },
  OM: {
    code: 'OM',
    name: 'Oman',
    shortName: 'Oman',
    label: 'All 11 governorates',
    regions: OMAN_GOVERNORATES,
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

/**
 * Reverse lookup: full country name (as used for .xlsx sheet tab names,
 * see multiCategoryOrchestrator.js's `uploadCategoryArchiveNow`) back to
 * its code — used when resuming an interrupted scan, to figure out which
 * countries an already-uploaded archive's sheets belong to. `null` if
 * nothing matches (e.g. the workbook's lone empty-placeholder "Leads" sheet).
 */
export function countryCodeForName(name) {
  const match = Object.values(COUNTRIES).find((c) => c.name === name);
  return match ? match.code : null;
}
