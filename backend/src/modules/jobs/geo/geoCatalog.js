/**
 * The geographic catalog behind the Jobs Finder search hierarchy:
 *
 *   Country -> State / Province -> City
 *
 * One JSON file per country in `src/data/jobs/geo/` (see geoImport.js for the
 * format and the importers). Adding a country is dropping a file in — nothing
 * in the search engine names a country. `JOBS_GEO_DIR` points at an extra
 * directory whose files override/extend the built-in ones.
 *
 * Datasets are read lazily and cached for the life of the process.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fold } from '../utils/text.js';
import { validateCountryDataset } from './geoImport.js';
import { WORLDWIDE_CODE } from '../models/constants.js';

const BUILTIN_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../data/jobs/geo');

/** The pseudo-country for remote work anywhere: no regions or cities. */
export const WORLDWIDE = Object.freeze({
  code: WORLDWIDE_CODE,
  name: 'Worldwide / Remote',
  aliases: ['worldwide', 'remote', 'anywhere', 'global'],
  adminLabel: null,
  regions: [],
  remoteOnly: true,
});

/** "D.C." and "dc" are the same short code. */
const codeKey = (token) => String(token || '').trim().toLowerCase().replace(/\./g, '');

export function createGeoCatalog({ dirs = [BUILTIN_DIR, process.env.JOBS_GEO_DIR].filter(Boolean), fsImpl = fs } = {}) {
  /** @type {Map<string, object> | null} */
  let countries = null;

  function load() {
    if (countries) return countries;
    const map = new Map([[WORLDWIDE.code, indexCountry(WORLDWIDE)]]);
    for (const dir of dirs) {
      let files = [];
      try {
        files = fsImpl.readdirSync(dir).filter((f) => f.endsWith('.json'));
      } catch {
        continue; // a missing optional directory is fine
      }
      for (const file of files) {
        try {
          const data = JSON.parse(fsImpl.readFileSync(path.join(dir, file), 'utf8'));
          validateCountryDataset(data);
          map.set(data.code, indexCountry(data));
        } catch (err) {
          // One broken file must not take the catalog down; it is just not offered.
          console.warn(`[jobs.geo] skipped ${file}: ${err.message}`);
        }
      }
    }
    countries = map;
    return map;
  }

  function indexCountry(data) {
    const regionsByName = new Map();
    const regionsByCode = new Map();
    for (const region of data.regions) {
      const indexed = { ...region, cityByName: new Map(region.cities.map((c) => [fold(c.name), c])) };
      regionsByName.set(fold(region.name), indexed);
      if (region.code) regionsByCode.set(String(region.code).toLowerCase(), indexed);
    }
    const names = [data.name, ...(data.aliases || [])].map(fold);
    return {
      ...data,
      regionsByName,
      regionsByCode,
      names,
      cityCount: data.regions.reduce((n, r) => n + r.cities.length, 0),
    };
  }

  /** Resolves [parts] inside [country] (dropping a trailing country token) or across all countries. */
  function parseWith(parts, country, dropLast) {
    const result = { countryCode: null, country: null, state: null, city: null };
    const rest = country && dropLast ? parts.slice(0, -1) : parts;
    const candidates = country ? [country] : [...load().values()].filter((c) => !c.remoteOnly);
    let region = null;
    let regionCountry = null;
    for (const token of [...rest].reverse()) {
      const hits = candidates
        .map((c) => ({ c, r: c.regionsByName.get(fold(token)) || c.regionsByCode.get(codeKey(token)) }))
        .filter((h) => h.r);
      if (hits.length === 1) {
        region = hits[0].r;
        regionCountry = hits[0].c;
        break;
      }
      if (hits.length > 1) break; // ambiguous across countries: leave unknown
    }
    const resolved = country || regionCountry;
    if (resolved) {
      result.countryCode = resolved.code;
      result.country = resolved.name;
    }
    if (region) result.state = region.name;
    const scope = region ? [region] : resolved ? resolved.regions.map((r) => resolved.regionsByName.get(fold(r.name))) : [];
    for (const token of rest) {
      const hit = scope.map((r) => r?.cityByName.get(fold(token))).find(Boolean);
      if (hit) {
        result.city = hit.name;
        break;
      }
    }
    return result;
  }

  const api = {
    /** Forget cached datasets (tests / after files change). */
    reload() {
      countries = null;
    },

    listCountries() {
      return [...load().values()]
        .map((c) => ({
          code: c.code,
          name: c.name,
          adminLabel: c.adminLabel,
          regionCount: c.regions.length,
          cityCount: c.cityCount,
          remoteOnly: Boolean(c.remoteOnly),
        }))
        .sort((a, b) => (a.code === WORLDWIDE_CODE ? 1 : b.code === WORLDWIDE_CODE ? -1 : a.name.localeCompare(b.name)));
    },

    getCountry(code) {
      return load().get(String(code || '').toUpperCase()) || null;
    },

    listRegions(countryCode) {
      const c = api.getCountry(countryCode);
      if (!c) return null;
      return c.regions.map((r) => ({ code: r.code, name: r.name, cityCount: r.cities.length }));
    },

    getRegion(countryCode, region) {
      const c = api.getCountry(countryCode);
      if (!c) return null;
      const key = fold(region);
      return c.regionsByName.get(key) || c.regionsByCode.get(codeKey(region)) || null;
    },

    /** Cities of one region (largest first), optionally filtered by text. */
    listCities(countryCode, region, { q, limit = 500, offset = 0 } = {}) {
      const r = api.getRegion(countryCode, region);
      if (!r) return null;
      const needle = fold(q);
      const all = needle ? r.cities.filter((c) => fold(c.name).includes(needle)) : r.cities;
      return { total: all.length, cities: all.slice(offset, offset + limit).map((c) => ({ name: c.name, population: c.population })) };
    },

    /**
     * Matches "United States", "usa", "DE" … to a country code, or null.
     * The Worldwide/Remote pseudo-country is only matched when asked for.
     */
    findCountryCode(text, { iso = true, worldwide = false } = {}) {
      const key = fold(text);
      if (!key) return null;
      for (const c of load().values()) {
        if (c.remoteOnly && !worldwide) continue;
        if ((iso && c.code.toLowerCase() === key) || c.names.includes(key)) return c.code;
      }
      return null;
    },

    /** Is [token] the short code or name of a region in any country ("CA" -> California)? */
    isRegionToken(token) {
      const lower = codeKey(token);
      const key = fold(token);
      return [...load().values()].some((c) => c.regionsByCode.has(lower) || c.regionsByName.has(key));
    },

    /**
     * Best-effort structure from a free-text location such as
     * "San Francisco, CA" or "Doha, Qatar". Only what can be matched
     * unambiguously is filled in; everything else stays null.
     *
     * A trailing two-letter token can be a country ("Berlin, DE") or a state
     * ("Wilmington, DE"); the reading under which the preceding city exists wins.
     */
    parseLocation(text, { countryHint = null } = {}) {
      const parts = String(text || '').split(/[,;|/]| - /).map((p) => p.trim()).filter(Boolean);
      const none = { countryCode: null, country: null, state: null, city: null };
      if (!parts.length) return none;

      const lastToken = parts[parts.length - 1];
      const named = api.findCountryCode(lastToken, { iso: false });
      const iso = api.findCountryCode(lastToken, { iso: true });
      const ambiguousIso = iso && !named && api.isRegionToken(lastToken);

      if (countryHint) return parseWith(parts, api.getCountry(countryHint), false);
      if (named) return parseWith(parts, api.getCountry(named), true);
      if (!ambiguousIso) return iso ? parseWith(parts, api.getCountry(iso), true) : parseWith(parts, null, false);

      const asCountry = parseWith(parts, api.getCountry(iso), true);
      const asRegion = parseWith(parts, null, false);
      if (asCountry.city && !asRegion.city) return asCountry;
      return asRegion.countryCode ? asRegion : asCountry;
    },

    /** Number of search locations a selection expands to — for estimates. */
    countLocations({ countryCode, regions = 'all', cities = 'all' }) {
      const c = api.getCountry(countryCode);
      if (!c) return 0;
      if (c.remoteOnly) return 1;
      const selected = regions === 'all' ? c.regions : c.regions.filter((r) => regions.includes(r.name) || regions.includes(r.code));
      if (cities === 'all') return selected.reduce((n, r) => n + r.cities.length, 0);
      return selected.reduce((n, r) => n + r.cities.filter((ct) => cities.includes(ct.name)).length, 0);
    },
  };
  return api;
}

/** Process-wide catalog (the datasets are read once). */
export const geoCatalog = createGeoCatalog();
