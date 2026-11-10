/**
 * Builds country datasets (country -> state/province -> city) from public
 * sources, in the format `geoCatalog.js` reads:
 *
 *   { code, name, aliases, adminLabel, regions: [{ code, name, cities: [{ name, population }] }] }
 *
 * Two input formats are supported, so a new country never needs code:
 *   - GeoNames dumps (`citiesNNNN.txt` + `admin1CodesASCII.txt`),
 *   - plain CSV with the columns  region,city[,population[,region_code]].
 *
 * GeoNames data is CC-BY 4.0 (https://www.geonames.org) — keep the
 * attribution in `source` when shipping a generated file.
 */

import { fold } from '../utils/text.js';

export class DatasetError extends Error {}

const clean = (s) => String(s ?? '').trim();

/** "US.CA\tCalifornia\t…" -> Map("US.CA" -> "California"). */
export function parseGeoNamesAdmin1(text) {
  const map = new Map();
  for (const line of String(text).split('\n')) {
    const [code, name, ascii] = line.split('\t');
    if (code && (name || ascii)) map.set(code, clean(ascii || name));
  }
  return map;
}

/**
 * @param {object} opts
 * @param {string} opts.countryCode   ISO-3166 alpha-2
 * @param {string} opts.countryName
 * @param {string} opts.citiesText    contents of a GeoNames `cities*.txt`
 * @param {string} opts.admin1Text    contents of `admin1CodesASCII.txt`
 * @param {number} [opts.minPopulation]
 * @param {string} [opts.adminLabel]  "State", "Province", "Emirate" …
 * @param {Record<string,string>} [opts.regionCodes]  admin1 code -> short code (e.g. "08" -> "ON")
 * @param {Record<string,string>} [opts.regionNames]  admin1 code -> display name, where GeoNames' is unfriendly
 * @param {string[]} [opts.aliases]
 */
export function buildCountryFromGeoNames({ countryCode, countryName, citiesText, admin1Text, minPopulation = 0, adminLabel = 'State', regionCodes = {}, regionNames = {}, aliases = [], source = 'GeoNames (CC-BY 4.0)' }) {
  const cc = clean(countryCode).toUpperCase();
  const admin1 = parseGeoNamesAdmin1(admin1Text);
  const regions = new Map(); // admin1 code -> { code, name, cities: Map(name -> pop) }

  for (const line of String(citiesText).split('\n')) {
    const f = line.split('\t');
    if (f.length < 15 || f[8] !== cc) continue;
    const population = Number(f[14]) || 0;
    if (population < minPopulation) continue;
    const name = clean(f[2] || f[1]); // ASCII name: stable across alphabets
    const adminCode = clean(f[10]) || '00';
    if (!name) continue;
    const key = adminCode;
    if (!regions.has(key)) {
      regions.set(key, { code: regionCodes[adminCode] || adminCode, name: regionNames[adminCode] || admin1.get(`${cc}.${adminCode}`) || `Region ${adminCode}`, cities: new Map() });
    }
    const cities = regions.get(key).cities;
    cities.set(name, Math.max(cities.get(name) || 0, population));
  }

  return finish({ code: cc, name: countryName, aliases, adminLabel, source, regions });
}

/** Minimal RFC-4180 CSV parser (quoted fields, "" escapes, CRLF). */
export function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  const s = String(text).replace(/^﻿/, '');
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (quoted) {
      if (ch === '"' && s[i + 1] === '"') {
        field += '"';
        i++;
      } else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && s[i + 1] === '\n') i++;
      row.push(field);
      field = '';
      if (row.some((c) => c.trim() !== '')) rows.push(row);
      row = [];
    } else field += ch;
  }
  row.push(field);
  if (row.some((c) => c.trim() !== '')) rows.push(row);
  return rows;
}

/**
 * CSV with a header row containing `region` and `city` (plus optional
 * `population`, `region_code`). Rows without a region are filed under the
 * country itself (for countries with no states).
 */
export function buildCountryFromCsv({ countryCode, countryName, csvText, adminLabel = 'State', aliases = [], source = 'CSV import' }) {
  const rows = parseCsv(csvText);
  if (!rows.length) throw new DatasetError('The CSV is empty');
  const header = rows[0].map((h) => fold(h).replace(/ /g, '_'));
  const col = (name) => header.indexOf(name);
  const [iRegion, iCity, iPop, iCode] = [col('region'), col('city'), col('population'), col('region_code')];
  if (iCity === -1) throw new DatasetError('The CSV needs a "city" column (and normally a "region" column)');

  const regions = new Map();
  for (const r of rows.slice(1)) {
    const city = clean(r[iCity]);
    if (!city) continue;
    const regionName = iRegion === -1 ? '' : clean(r[iRegion]);
    const name = regionName || countryName;
    const key = fold(name);
    if (!regions.has(key)) regions.set(key, { code: iCode === -1 ? '' : clean(r[iCode]), name, cities: new Map() });
    const pop = iPop === -1 ? 0 : Number(String(r[iPop]).replace(/[, ]/g, '')) || 0;
    const cities = regions.get(key).cities;
    cities.set(city, Math.max(cities.get(city) || 0, pop));
  }
  if (!regions.size) throw new DatasetError('The CSV has no usable rows');
  return finish({ code: clean(countryCode).toUpperCase(), name: countryName, aliases, adminLabel, source, regions });
}

function finish({ code, name, aliases, adminLabel, source, regions }) {
  const list = [...regions.values()]
    .map((r) => ({
      code: r.code || fold(r.name).replace(/ /g, '-').toUpperCase().slice(0, 12),
      name: r.name,
      cities: [...r.cities.entries()].map(([n, population]) => ({ name: n, population })).sort((a, b) => b.population - a.population || a.name.localeCompare(b.name)),
    }))
    .filter((r) => r.cities.length)
    .sort((a, b) => a.name.localeCompare(b.name));
  const dataset = { code, name, aliases, adminLabel, source, regions: list };
  validateCountryDataset(dataset);
  return dataset;
}

/** Throws [DatasetError] unless [d] is a usable country dataset. */
export function validateCountryDataset(d) {
  if (!d || typeof d !== 'object') throw new DatasetError('Dataset must be an object');
  if (!/^[A-Z]{2}$/.test(d.code || '')) throw new DatasetError('Dataset "code" must be a 2-letter country code');
  if (!clean(d.name)) throw new DatasetError('Dataset "name" is required');
  if (!Array.isArray(d.regions)) throw new DatasetError('Dataset "regions" must be an array');
  const seen = new Set();
  for (const r of d.regions) {
    if (!clean(r?.name)) throw new DatasetError('Every region needs a name');
    const key = fold(r.name);
    if (seen.has(key)) throw new DatasetError(`Duplicate region "${r.name}"`);
    seen.add(key);
    if (!Array.isArray(r.cities)) throw new DatasetError(`Region "${r.name}" needs a cities array`);
    for (const c of r.cities) if (!clean(c?.name)) throw new DatasetError(`Region "${r.name}" has a city without a name`);
  }
  return d;
}
