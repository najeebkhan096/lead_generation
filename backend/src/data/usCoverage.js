/**
 * Which places a scan searches, in three tiers:
 *
 *   standard  the 10 largest cities per state (501 searches). Quick.
 *   extended  every incorporated place of 25,000+ people, plus the standard
 *             list (about 1,600 searches). Most leads per hour of scanning.
 *   maximum   every place of 5,000+ people, and for cities of 100,000+ a grid
 *             of search points across the city, because Google returns only
 *             about 120 results per search and a big city has far more
 *             businesses than that (several thousand searches).
 *
 * Each state is `{ state, cities: [names], specs: { name: { lat, lng, zoom } } }`.
 * A name with a `spec` is searched around that point on the map instead of by
 * place name (the grid points of a large city).
 */

import { US_STATE_CITIES } from './usStateCities.js';
import census from './usPlaces.json' with { type: 'json' };

export const COVERAGE_TIERS = Object.freeze({
  standard: { label: 'Standard', minPopulation: null, grid: false },
  extended: { label: 'Extended', minPopulation: 25000, grid: false },
  maximum: { label: 'Maximum', minPopulation: 5000, grid: true },
});

export function isCoverageTier(value) {
  return Object.prototype.hasOwnProperty.call(COVERAGE_TIERS, value);
}

const GRID_MIN_POPULATION = 100000;
const GRID_SPACING_MILES = 3;
const GRID_MAX_AREA_SQMI = 700; // a huge consolidated city is not tiled across its whole land area
const GRID_MAX_POINTS = 60;
const GRID_ZOOM = 14;

/** Search points covering a city: a square grid, in miles, inside its (circular) extent. */
export function gridPoints({ lat, lng, area }, spacing = GRID_SPACING_MILES) {
  const radius = Math.sqrt(Math.min(area, GRID_MAX_AREA_SQMI) / Math.PI);
  if (!(radius > spacing * 0.75)) return []; // small enough for the one search by name
  const dLat = spacing / 69;
  const dLng = spacing / (69 * Math.cos((lat * Math.PI) / 180));
  const n = Math.floor(radius / spacing);
  const points = [];
  for (let iy = -n; iy <= n; iy++) {
    for (let ix = -n; ix <= n; ix++) {
      if (Math.hypot(ix * spacing, iy * spacing) > radius) continue;
      if (ix === 0 && iy === 0) continue; // the centre is the search by name
      points.push({ lat: +(lat + iy * dLat).toFixed(4), lng: +(lng + ix * dLng).toFixed(4) });
    }
  }
  // Too many for one city: keep an evenly spread subset rather than a corner.
  if (points.length > GRID_MAX_POINTS) {
    const step = points.length / GRID_MAX_POINTS;
    return Array.from({ length: GRID_MAX_POINTS }, (_, i) => points[Math.floor(i * step)]);
  }
  return points;
}

/**
 * @param {'standard'|'extended'|'maximum'} tier
 * @param {{ curated?: typeof US_STATE_CITIES, data?: typeof census }} [sources]
 */
export function buildCoverage(tier = 'standard', { curated = US_STATE_CITIES, data = census } = {}) {
  const cfg = COVERAGE_TIERS[tier];
  if (!cfg) throw new Error(`Unknown coverage "${tier}". Use standard, extended or maximum.`);
  if (!cfg.minPopulation) return curated.map((s) => ({ state: s.state, cities: [...s.cities], specs: {} }));

  const byState = new Map(data.states.map((s) => [s.state, s.places]));
  return curated.map((entry) => {
    const places = (byState.get(entry.state) || []).filter((p) => p.p >= cfg.minPopulation);
    const cities = [];
    const specs = {};
    const seen = new Set();
    const add = (name) => {
      if (seen.has(name.toLowerCase())) return false;
      seen.add(name.toLowerCase());
      cities.push(name);
      return true;
    };

    // The curated list first (it covers places Census does not list, e.g. Hawaii and D.C.).
    for (const name of entry.cities) add(name);
    for (const place of places) add(place.n);

    if (cfg.grid) {
      for (const place of places) {
        if (place.p < GRID_MIN_POPULATION) continue;
        const points = gridPoints({ lat: place.lat, lng: place.lng, area: place.a });
        points.forEach((pt, i) => {
          const name = `${place.n} · area ${i + 1}/${points.length}`;
          if (add(name)) specs[name] = { lat: pt.lat, lng: pt.lng, zoom: GRID_ZOOM, within: place.n };
        });
      }
    }
    return { state: entry.state, cities, specs };
  });
}

/** Rough size of a tier, for the scan page: searches, and the businesses and hours they imply. */
export function describeCoverage(tier, perMinute = 20) {
  const coverage = buildCoverage(tier);
  const searches = coverage.reduce((n, s) => n + s.cities.length, 0);
  // From the Alabama scan: ~28 businesses read per city, and about 40% of those
  // are repeats once neighbouring cities and grid points overlap.
  const businesses = Math.round(searches * 28 * 0.6);
  return { tier, label: COVERAGE_TIERS[tier].label, searches, businesses, hours: Math.round((businesses / perMinute / 60) * 10) / 10 };
}
