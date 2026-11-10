#!/usr/bin/env node
/**
 * Builds Jobs Finder country datasets from GeoNames (CC-BY 4.0) or a CSV.
 *
 *   # from GeoNames dumps you downloaded (https://download.geonames.org/export/dump/)
 *   node scripts/importGeoNames.mjs --cities cities5000.txt --admin1 admin1CodesASCII.txt \
 *        --country US --name "United States" --label State --alias USA --alias "U.S." \
 *        [--min-population 5000] [--out src/data/jobs/geo]
 *
 *   # from a CSV with columns region,city[,population[,region_code]]
 *   node scripts/importGeoNames.mjs --csv france.csv --country FR --name France --label Region
 *
 * The result is one JSON file per country; the search engine picks it up on
 * the next start. Nothing else needs to change to add a country.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCountryFromGeoNames, buildCountryFromCsv } from '../src/modules/jobs/geo/geoImport.js';

// Short codes for regions whose GeoNames admin1 code is only a number.
const REGION_CODES = {
  CA: { '01': 'AB', '02': 'BC', '03': 'MB', '04': 'NB', '05': 'NL', '07': 'NS', '08': 'ON', '09': 'PE', '10': 'QC', '11': 'SK', '12': 'YT', '13': 'NT', '14': 'NU' },
  DE: { '01': 'BW', '02': 'BY', '03': 'HB', '04': 'HH', '05': 'HE', '06': 'NI', '07': 'NW', '08': 'RP', '09': 'SL', '10': 'SN', '11': 'ST', '12': 'SH', '13': 'TH', '14': 'BB', '15': 'MV', '16': 'BE' },
};

// Display names where GeoNames' administrative names are unfriendly.
const REGION_NAMES = {
  QA: { '13': 'Al Daayen', '04': 'Al Khor', '10': 'Al Wakrah', '14': 'Al Shahaniya', '01': 'Doha', '06': 'Al Rayyan', '08': 'Al Shamal', '09': 'Umm Salal' },
  SA: { '11': 'Asir', '02': 'Al Bahah', '20': 'Al Jawf', '08': 'Al Qassim', '06': 'Eastern Province', '13': 'Hail', '17': 'Jazan', '14': 'Makkah', '05': 'Madinah', '16': 'Najran', '15': 'Northern Borders', '10': 'Riyadh', '19': 'Tabuk' },
};

function parseArgs(argv) {
  const args = { alias: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) throw new Error(`Unexpected argument ${a}`);
    const key = a.slice(2);
    const value = argv[++i];
    if (value === undefined) throw new Error(`--${key} needs a value`);
    if (key === 'alias') args.alias.push(value);
    else args[key] = value;
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.country || !args.name) throw new Error('--country and --name are required');
  const out = path.resolve(args.out || path.join(path.dirname(fileURLToPath(import.meta.url)), '../src/data/jobs/geo'));
  const read = (p) => fs.readFileSync(path.resolve(p), 'utf8');

  let dataset;
  if (args.csv) {
    dataset = buildCountryFromCsv({ countryCode: args.country, countryName: args.name, csvText: read(args.csv), adminLabel: args.label || 'State', aliases: args.alias });
  } else if (args.cities && args.admin1) {
    dataset = buildCountryFromGeoNames({
      countryCode: args.country,
      countryName: args.name,
      citiesText: read(args.cities),
      admin1Text: read(args.admin1),
      minPopulation: Number(args['min-population'] || 0),
      adminLabel: args.label || 'State',
      regionCodes: REGION_CODES[args.country.toUpperCase()] || {},
      regionNames: REGION_NAMES[args.country.toUpperCase()] || {},
      aliases: args.alias,
    });
  } else {
    throw new Error('Give either --csv FILE, or --cities FILE --admin1 FILE');
  }

  fs.mkdirSync(out, { recursive: true });
  const file = path.join(out, `${dataset.code}.json`);
  fs.writeFileSync(file, JSON.stringify(dataset));
  const cities = dataset.regions.reduce((n, r) => n + r.cities.length, 0);
  console.log(`${dataset.code}: ${dataset.regions.length} regions, ${cities} cities -> ${file}`);
}

try {
  main();
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
