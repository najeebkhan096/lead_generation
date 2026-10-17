/**
 * Builds src/data/usPlaces.json from the U.S. Census Bureau's public files:
 *   - population estimates for every incorporated place (sub-est2023.csv)
 *   - the Gazetteer of places: centre coordinates and land area
 *
 *   node scripts/buildUsPlaces.mjs [dir-with-the-files]
 *
 * Downloads them into the given folder (default /tmp/census) if missing. The
 * output keeps places of 5,000 people or more, per state, largest first:
 *   { states: [{ state, places: [{ n: name, p: population, lat, lng, a: sq mi }] }] }
 * The scan uses it for its "Extended" and "Maximum" coverage (more cities than
 * the 10 per state it started with; very large cities become a grid of search
 * points). Run again to refresh from newer Census releases.
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const dir = process.argv[2] || '/tmp/census';
const here = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(here, '../src/data/usPlaces.json');
const MIN_POP = 5000;

const FILES = {
  pop: ['sub-est2023.csv', 'https://www2.census.gov/programs-surveys/popest/datasets/2020-2023/cities/totals/sub-est2023.csv'],
  gaz: ['2023_Gaz_place_national.txt', 'https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_place_national.zip'],
};

fs.mkdirSync(dir, { recursive: true });
async function ensure([name, url]) {
  const file = path.join(dir, name);
  if (fs.existsSync(file)) return file;
  console.log('downloading', url);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (url.endsWith('.zip')) {
    const zip = path.join(dir, path.basename(url));
    fs.writeFileSync(zip, buf);
    fs.writeFileSync(file, execFileSync('unzip', ['-p', zip, name]));
  } else {
    fs.writeFileSync(file, buf);
  }
  return file;
}

function parseCsvLine(line) {
  const out = [];
  let cur = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (ch === '"') quoted = false;
      else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { out.push(cur); cur = ''; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}

/** "Birmingham city" -> "Birmingham"; "Nashville-Davidson metropolitan government (balance)" -> "Nashville". */
export function cleanPlaceName(raw) {
  let n = String(raw).replace(/\s*\(.*?\)\s*/g, ' ').trim();
  n = n.replace(/\s+(city and borough|consolidated government|metropolitan government|metro government|urban county|unified government|municipality|borough|village|town|city|CDP)$/i, '').trim();
  const special = {
    'Nashville-Davidson': 'Nashville',
    'Louisville/Jefferson County': 'Louisville',
    'Lexington-Fayette': 'Lexington',
    'Augusta-Richmond County': 'Augusta',
    'Athens-Clarke County': 'Athens',
    'Macon-Bibb County': 'Macon',
    'Urban Honolulu': 'Honolulu',
    'Kansas City': 'Kansas City',
  };
  return special[n] || n;
}

const popFile = await ensure(FILES.pop);
const gazFile = await ensure(FILES.gaz);

// geoid (state+place fips) -> { lat, lng, area }
const gaz = new Map();
const gazLines = fs.readFileSync(gazFile, 'utf8').split('\n');
const gh = gazLines[0].split('\t').map((h) => h.trim());
const col = (name) => gh.indexOf(name);
for (const line of gazLines.slice(1)) {
  const c = line.split('\t');
  if (c.length < gh.length) continue;
  gaz.set(c[col('GEOID')].trim(), {
    lat: Number(c[col('INTPTLAT')]),
    lng: Number(c[col('INTPTLONG')]),
    area: Number(c[col('ALAND_SQMI')]),
  });
}

const rows = fs.readFileSync(popFile, 'utf8').split('\n');
const h = parseCsvLine(rows[0]);
const ix = Object.fromEntries(h.map((name, i) => [name, i]));
const byState = new Map();
for (const line of rows.slice(1)) {
  if (!line.trim()) continue;
  const c = parseCsvLine(line);
  if (c[ix.SUMLEV] !== '162' || c[ix.FUNCSTAT] !== 'A') continue; // incorporated, active places
  const pop = Number(c[ix.POPESTIMATE2023]);
  if (!(pop >= MIN_POP)) continue;
  const geo = gaz.get(c[ix.STATE] + c[ix.PLACE]);
  if (!geo || !Number.isFinite(geo.lat)) continue;
  const state = c[ix.STNAME];
  const place = { n: cleanPlaceName(c[ix.NAME]), p: pop, lat: +geo.lat.toFixed(4), lng: +geo.lng.toFixed(4), a: +geo.area.toFixed(1) };
  if (!byState.has(state)) byState.set(state, []);
  byState.get(state).push(place);
}

const states = [...byState.entries()]
  .map(([state, places]) => {
    // Largest first; if two places clean to the same name keep the larger.
    places.sort((a, b) => b.p - a.p);
    const seen = new Set();
    return { state, places: places.filter((p) => (seen.has(p.n.toLowerCase()) ? false : seen.add(p.n.toLowerCase()))) };
  })
  .sort((a, b) => a.state.localeCompare(b.state));

fs.writeFileSync(OUT, JSON.stringify({ source: 'U.S. Census Bureau: 2023 population estimates + Gazetteer', minPopulation: MIN_POP, states }));
const total = states.reduce((n, s) => n + s.places.length, 0);
console.log(`wrote ${OUT}: ${states.length} states, ${total} places >= ${MIN_POP} (${(fs.statSync(OUT).size / 1024).toFixed(0)} KB)`);
for (const t of [100000, 50000, 25000, 15000, 10000, 5000]) console.log(`  >= ${t}: ${states.reduce((n, s) => n + s.places.filter((p) => p.p >= t).length, 0)}`);
