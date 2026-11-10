import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createGeoCatalog, geoCatalog } from './geoCatalog.js';
import { buildCountryFromGeoNames, buildCountryFromCsv, parseCsv, validateCountryDataset, DatasetError } from './geoImport.js';

test('the built-in catalog covers the required countries with full state and city lists', () => {
  const byCode = Object.fromEntries(geoCatalog.listCountries().map((c) => [c.code, c]));
  for (const code of ['US', 'QA', 'AE', 'SA', 'CA', 'DE', 'WW']) assert.ok(byCode[code], code);
  assert.equal(byCode.US.regionCount, 51, '50 states + DC');
  assert.ok(byCode.US.cityCount > 5000, `${byCode.US.cityCount} US cities`);
  assert.equal(byCode.DE.regionCount, 16);
  assert.equal(byCode.CA.regionCount, 13, '10 provinces + 3 territories');
  assert.equal(byCode.AE.regionCount, 7, 'the seven emirates');
  assert.equal(byCode.WW.remoteOnly, true);
  assert.equal(byCode.WW.regionCount, 0);
});

test('the example cities from the brief are all present', () => {
  const has = (state, city) => geoCatalog.listCities('US', state, { q: city, limit: 50 }).cities.some((c) => c.name === city);
  for (const [state, cities] of Object.entries({
    California: ['Los Angeles', 'San Francisco', 'San Diego', 'Sacramento'],
    Texas: ['Houston', 'Dallas', 'Austin'],
    'New York': ['New York City', 'Buffalo', 'Albany'],
    Florida: ['Miami', 'Orlando', 'Tampa'],
  })) for (const city of cities) assert.ok(has(state, city), `${city}, ${state}`);
});

test('cities are listed largest first, can be filtered by text and paged', () => {
  const all = geoCatalog.listCities('US', 'California', { limit: 3 });
  assert.equal(all.cities[0].name, 'Los Angeles');
  assert.ok(all.cities[0].population > all.cities[1].population);
  const sub = geoCatalog.listCities('US', 'California', { q: 'san f' });
  assert.ok(sub.cities.every((c) => /san f/i.test(c.name)));
  const p1 = geoCatalog.listCities('US', 'California', { limit: 2, offset: 0 }).cities;
  const p2 = geoCatalog.listCities('US', 'California', { limit: 2, offset: 2 }).cities;
  assert.notDeepEqual(p1, p2);
  assert.equal(geoCatalog.listCities('US', 'Atlantis'), null);
  assert.equal(geoCatalog.getRegion('US', 'ca').name, 'California', 'regions resolve by short code too');
});

test('free-text locations resolve to structure, resolving ambiguity by the city that exists', () => {
  const p = (t) => geoCatalog.parseLocation(t);
  assert.deepEqual(p('San Francisco, CA'), { countryCode: 'US', country: 'United States', state: 'California', city: 'San Francisco' });
  assert.deepEqual(p('Berlin, DE').countryCode, 'DE');
  assert.deepEqual([p('Wilmington, DE').countryCode, p('Wilmington, DE').state], ['US', 'Delaware']);
  assert.equal(p('Toronto, CA').countryCode, 'CA');
  assert.equal(p('Munich, Bavaria, Germany').city, 'Munich');
  assert.equal(p('Doha, Qatar').countryCode, 'QA');
  assert.equal(p('Washington, D.C.').state, 'District of Columbia');
  assert.deepEqual(p('Remote'), { countryCode: null, country: null, state: null, city: null }, '"Remote" is not a country');
  assert.deepEqual(p('Springfield'), { countryCode: null, country: null, state: null, city: null }, 'ambiguous or unknown stays null');
  assert.deepEqual(p(''), { countryCode: null, country: null, state: null, city: null });
});

test('countries are found by name, alias or code; the Worldwide pseudo-country only when asked', () => {
  assert.equal(geoCatalog.findCountryCode('USA'), 'US');
  assert.equal(geoCatalog.findCountryCode('united states'), 'US');
  assert.equal(geoCatalog.findCountryCode('UAE'), 'AE');
  assert.equal(geoCatalog.findCountryCode('Deutschland'), 'DE');
  assert.equal(geoCatalog.findCountryCode('remote'), null);
  assert.equal(geoCatalog.findCountryCode('remote', { worldwide: true }), 'WW');
});

test('a country is added by dropping a file in a directory — no code involved', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'geo-'));
  fs.writeFileSync(path.join(dir, 'FR.json'), JSON.stringify({ code: 'FR', name: 'France', aliases: ['République française'], adminLabel: 'Region', regions: [{ code: 'IDF', name: 'Île-de-France', cities: [{ name: 'Paris', population: 2100000 }] }] }));
  fs.writeFileSync(path.join(dir, 'BROKEN.json'), '{ nope');
  fs.writeFileSync(path.join(dir, 'BAD.json'), JSON.stringify({ code: 'XXX', name: 'Bad', regions: [] }));
  const catalog = createGeoCatalog({ dirs: [dir] });
  const codes = catalog.listCountries().map((c) => c.code);
  assert.deepEqual(codes.sort(), ['FR', 'WW'], 'broken and invalid files are skipped, not fatal');
  assert.equal(catalog.listCities('FR', 'Ile-de-France').cities[0].name, 'Paris', 'accents fold in lookups');
  assert.equal(catalog.parseLocation('Paris, France').city, 'Paris');
});

test('GeoNames import: filters by population, names regions from admin1 codes, keeps the largest of same-named places', () => {
  const row = (name, country, admin1, pop) => ['1', name, name, '', '0', '0', 'P', 'PPL', country, '', admin1, '', '', '', String(pop), '', '', 'UTC', '2020-01-01'].join('\t');
  const citiesText = [row('Austin', 'US', 'TX', 950000), row('Austin', 'US', 'TX', 6000), row('Tinyville', 'US', 'TX', 1200), row('Columbus', 'US', 'OH', 890000), row('Paris', 'FR', 'A8', 2100000)].join('\n');
  const admin1Text = 'US.TX\tTexas\tTexas\t4736286\nUS.OH\tOhio\tOhio\t5165418\nFR.A8\tÎle-de-France\tIle-de-France\t1\n';
  const us = buildCountryFromGeoNames({ countryCode: 'US', countryName: 'United States', citiesText, admin1Text, minPopulation: 5000, aliases: ['USA'] });
  assert.deepEqual(us.regions.map((r) => r.name), ['Ohio', 'Texas']);
  const tx = us.regions.find((r) => r.name === 'Texas');
  assert.deepEqual(tx.cities, [{ name: 'Austin', population: 950000 }], 'one Austin (the larger), Tinyville below the threshold');
  assert.equal(tx.code, 'TX');
  const renamed = buildCountryFromGeoNames({ countryCode: 'US', countryName: 'US', citiesText, admin1Text, regionCodes: { TX: 'T1' }, regionNames: { TX: 'Lone Star' } });
  assert.equal(renamed.regions.find((r) => r.code === 'T1').name, 'Lone Star');
});

test('CSV import handles quotes, BOM and missing columns; invalid files explain themselves', () => {
  const csv = '﻿region,city,population,region_code\r\nBavaria,Munich,1500000,BY\r\nBavaria,"Garmisch-Partenkirchen, Markt",26000,BY\r\nBerlin,Berlin,3600000,BE\r\n';
  const de = buildCountryFromCsv({ countryCode: 'de', countryName: 'Germany', csvText: csv });
  assert.equal(de.code, 'DE');
  assert.deepEqual(de.regions.map((r) => r.name), ['Bavaria', 'Berlin']);
  assert.equal(de.regions[0].cities[1].name, 'Garmisch-Partenkirchen, Markt');
  assert.deepEqual(parseCsv('a,"b ""q"" c"\n1,2'), [['a', 'b "q" c'], ['1', '2']]);

  const flat = buildCountryFromCsv({ countryCode: 'LU', countryName: 'Luxembourg', csvText: 'city\nLuxembourg\nEsch' });
  assert.equal(flat.regions[0].name, 'Luxembourg', 'a country without states is one region named after it');
  assert.throws(() => buildCountryFromCsv({ countryCode: 'XX', countryName: 'X', csvText: 'name\nA' }), DatasetError);
  assert.throws(() => buildCountryFromCsv({ countryCode: 'XX', countryName: 'X', csvText: '' }), /empty/);
  assert.throws(() => validateCountryDataset({ code: 'US', name: 'US', regions: [{ name: 'A', cities: [] }, { name: 'a', cities: [] }] }), /Duplicate region/);
});
