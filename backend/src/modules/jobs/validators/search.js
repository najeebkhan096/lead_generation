/** Validation of a job-search configuration (POST/PUT /api/jobs/searches). */

import { Problems, isObject, str, num, bool, strList } from './validate.js';
import { EMPLOYMENT_TYPES, WORK_ARRANGEMENTS, EXPERIENCE_LEVELS, WORLDWIDE_CODE } from '../models/constants.js';
import { fold } from '../utils/text.js';
import { invalid } from '../utils/errors.js';

export const DEFAULT_LIMITS = Object.freeze({ maxCombinations: 20_000, maxResultsPerCombination: 100, maxPagesPerSource: 3, concurrency: 3 });
export const LIMIT_CEILINGS = Object.freeze({ maxCombinations: 100_000, maxResultsPerCombination: 500, maxPagesPerSource: 10, concurrency: 8 });

function validateCountries(p, raw, catalog) {
  if (!Array.isArray(raw) || !raw.length) {
    p.add('countries', 'needs at least one country');
    return [];
  }
  if (raw.length > 12) p.add('countries', 'at most 12 countries per search');
  const out = [];
  const seen = new Set();
  raw.slice(0, 12).forEach((entry, i) => {
    const at = (f) => `countries[${i}].${f}`;
    if (!isObject(entry)) return p.add(`countries[${i}]`, 'must be an object');
    const code = String(entry.code || '').toUpperCase();
    const country = catalog.getCountry(code);
    if (!country) return p.add(at('code'), `unknown country "${entry.code}"`);
    if (seen.has(code)) return p.add(at('code'), `${code} is listed twice`);
    seen.add(code);

    if (country.remoteOnly) {
      out.push({ code, level: 'country', regions: 'all', cities: 'all', includeRemote: true });
      return;
    }
    const level = entry.level ?? 'city';
    if (!['country', 'state', 'city'].includes(level)) p.add(at('level'), 'must be country, state or city');

    let regions = 'all';
    if (entry.regions !== undefined && entry.regions !== 'all') {
      if (!Array.isArray(entry.regions) || !entry.regions.length) p.add(at('regions'), 'must be "all" or a non-empty list');
      else {
        regions = [];
        for (const name of entry.regions) {
          const r = catalog.getRegion(code, name);
          if (!r) p.add(at('regions'), `"${name}" is not a ${country.adminLabel || 'region'} of ${country.name}`);
          else regions.push(r.name);
        }
      }
    }

    let cities = 'all';
    if (level === 'city' && entry.cities !== undefined && entry.cities !== 'all') {
      if (!Array.isArray(entry.cities) || !entry.cities.length) p.add(at('cities'), 'must be "all" or a non-empty list of {state, city}');
      else {
        cities = [];
        for (const c of entry.cities) {
          const region = isObject(c) ? catalog.getRegion(code, c.state) : null;
          const city = region?.cityByName.get(fold(c.city));
          if (!city) p.add(at('cities'), `"${c?.city}, ${c?.state}" is not in the ${country.name} dataset`);
          else if (regions !== 'all' && !regions.includes(region.name)) p.add(at('cities'), `${region.name} is not among the selected ${country.adminLabel || 'region'}s`);
          else cities.push({ state: region.name, city: city.name });
        }
      }
    }
    out.push({ code, level, regions, cities, includeRemote: entry.includeRemote === true });
  });
  return out;
}

function validateFilters(parent, raw) {
  const p = parent.scope('filters');
  const f = isObject(raw) ? raw : {};
  const filters = {
    experienceLevel: str(p, f, 'experienceLevel', { oneOf: EXPERIENCE_LEVELS }),
    employmentType: str(p, f, 'employmentType', { oneOf: EMPLOYMENT_TYPES }),
    workArrangement: str(p, f, 'workArrangement', { oneOf: WORK_ARRANGEMENTS }),
    salaryMin: num(p, f, 'salaryMin', { min: 0, max: 10_000_000 }),
    salaryMax: num(p, f, 'salaryMax', { min: 0, max: 10_000_000 }),
    salaryCurrency: str(p, f, 'salaryCurrency', { pattern: /^[A-Za-z]{3}$/ })?.toUpperCase() ?? null,
    postedWithinDays: num(p, f, 'postedWithinDays', { min: 1, max: 365, integer: true }),
  };
  if (filters.salaryMin != null && filters.salaryMax != null && filters.salaryMin > filters.salaryMax) p.add('salaryMin', 'must not exceed salaryMax');
  return filters;
}

function validateSchedule(parent, raw) {
  const p = parent.scope('schedule');
  const s = isObject(raw) ? raw : {};
  const enabled = bool(p, s, 'enabled', false);
  const timeOfDay = str(p, s, 'timeOfDay', { pattern: /^([01]\d|2[0-3]):[0-5]\d$/, fallback: '03:00' });
  const timezone = str(p, s, 'timezone', { max: 60, fallback: 'UTC' });
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: timezone });
  } catch {
    p.add('timezone', `"${timezone}" is not a valid IANA time zone`);
  }
  return { enabled, timeOfDay, timezone, lastRunDate: typeof s.lastRunDate === 'string' ? s.lastRunDate : null };
}

/**
 * @param {object} body
 * @param {{catalog: object, sourceIds: string[], maxCombinations?: number}} deps
 * @returns the cleaned configuration (no ids / timestamps — the store adds those)
 */
export function validateSearch(body, { catalog, sourceIds }) {
  const p = new Problems();
  if (!isObject(body)) throw invalid('Body must be a JSON object');
  const name = str(p, body, 'name', { required: true, max: 80, min: 2 });
  const countries = validateCountries(p, body.countries, catalog);
  const titles = strList(p, body, 'titles', { max: 40, itemMax: 80, required: true });
  const keywords = strList(p, body, 'keywords', { max: 12, itemMax: 40 });
  const sources = strList(p, body, 'sources', { max: 20, itemMax: 40 });
  for (const s of sources) if (!sourceIds.includes(s)) p.add('sources', `unknown source "${s}"`);

  const l = isObject(body.limits) ? body.limits : {};
  const limits = {};
  const lp = p.scope('limits');
  for (const key of Object.keys(DEFAULT_LIMITS)) {
    limits[key] = num(lp, l, key, { min: 1, max: LIMIT_CEILINGS[key], integer: true, fallback: DEFAULT_LIMITS[key] });
  }

  const filters = validateFilters(p, body.filters);
  const schedule = validateSchedule(p, body.schedule);
  const enabled = bool(p, body, 'enabled', true);
  p.throwIfAny();
  return {
    name,
    enabled,
    countries,
    titles,
    keywords,
    filters,
    sources,
    limits,
    schedule,
    worldwide: countries.some((c) => c.code === WORLDWIDE_CODE),
  };
}
