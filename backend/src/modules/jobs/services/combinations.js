/**
 * Expands a search configuration into search combinations:
 *
 *   Country → State / Province → City × Job title
 *
 *   "California × Los Angeles × Flutter Developer"
 *   "California × Los Angeles × Senior Flutter Developer"
 *   "Texas × Houston × Flutter Developer" …
 *
 * A country entry says how deep to go (`level`):
 *   country  one location, the country itself
 *   state    every selected state/province (`regions`: 'all' or a list)
 *   city     every selected city (`cities`: 'all' or [{state, city}])
 * and `includeRemote` adds a country-level *remote* search per title.
 * The Worldwide/Remote pseudo-country is always one remote location.
 *
 * Nothing is materialised until asked: [countCombinations] is arithmetic, so
 * the UI can show "≈ 12,430 searches" for the whole of the US instantly, and
 * [iterateCombinations] yields lazily in a stable order (biggest cities first).
 */

import { titleKey, hashText } from '../utils/normalize.js';
import { WORLDWIDE_CODE } from '../models/constants.js';
import { fold } from '../utils/text.js';

/** Distinct, trimmed job titles (case/spacing-insensitive). */
export function uniqueTitles(titles) {
  const seen = new Set();
  const out = [];
  for (const raw of titles || []) {
    const t = String(raw ?? '').replace(/\s+/g, ' ').trim();
    const k = titleKey(t);
    if (t && k && !seen.has(k)) {
      seen.add(k);
      out.push(t);
    }
  }
  return out;
}

/** The locations (without titles) one country entry expands to. */
function* locationsOf(entry, catalog) {
  const country = catalog.getCountry(entry.code);
  if (!country) return;
  const base = { countryCode: country.code, country: country.name };

  if (country.remoteOnly) {
    yield { ...base, state: null, city: null, remoteOnly: true };
    return;
  }
  if (entry.level === 'country') {
    yield { ...base, state: null, city: null, remoteOnly: false };
  } else {
    const wanted = entry.regions === 'all' || !entry.regions ? null : new Set(entry.regions.map(fold));
    const regions = country.regions.filter((r) => !wanted || wanted.has(fold(r.name)) || wanted.has(fold(r.code)));
    if (entry.level === 'state') {
      for (const r of regions) yield { ...base, state: r.name, city: null, remoteOnly: false };
    } else {
      const chosen = Array.isArray(entry.cities) ? new Set(entry.cities.map((c) => `${fold(c.state)}|${fold(c.city)}`)) : null;
      for (const r of regions) {
        for (const c of r.cities) {
          if (chosen && !chosen.has(`${fold(r.name)}|${fold(c.name)}`)) continue;
          yield { ...base, state: r.name, city: c.name, remoteOnly: false };
        }
      }
    }
  }
  if (entry.includeRemote) yield { ...base, state: null, city: null, remoteOnly: true };
}

export function* iterateCombinations(search, catalog) {
  const titles = uniqueTitles(search.titles);
  for (const entry of search.countries || []) {
    for (const loc of locationsOf(entry, catalog)) {
      for (const title of titles) {
        const key = hashText(`${loc.countryCode}|${fold(loc.state)}|${fold(loc.city)}|${loc.remoteOnly ? 'r' : ''}|${titleKey(title)}`, 24);
        yield { key, ...loc, title };
      }
    }
  }
}

/** How many combinations [search] expands to, without expanding it. */
export function countCombinations(search, catalog) {
  const titles = uniqueTitles(search.titles).length;
  let locations = 0;
  for (const entry of search.countries || []) {
    const country = catalog.getCountry(entry.code);
    if (!country) continue;
    if (country.remoteOnly) {
      locations += 1;
      continue;
    }
    if (entry.level === 'country') locations += 1;
    else {
      const wanted = entry.regions === 'all' || !entry.regions ? null : new Set(entry.regions.map(fold));
      const regions = country.regions.filter((r) => !wanted || wanted.has(fold(r.name)) || wanted.has(fold(r.code)));
      if (entry.level === 'state') locations += regions.length;
      else if (Array.isArray(entry.cities)) {
        const chosen = new Set(entry.cities.map((c) => `${fold(c.state)}|${fold(c.city)}`));
        for (const r of regions) for (const c of r.cities) if (chosen.has(`${fold(r.name)}|${fold(c.name)}`)) locations += 1;
      } else locations += regions.reduce((n, r) => n + r.cities.length, 0);
    }
    if (entry.includeRemote) locations += 1;
  }
  return { locations, titles, combinations: locations * titles };
}

/** A short human label: "California › Los Angeles · Flutter Developer". */
export function describeCombination(c) {
  const where = c.remoteOnly ? `${c.countryCode === WORLDWIDE_CODE ? 'Worldwide' : c.country} (remote)` : [c.country, c.state, c.city].filter((v, i, a) => v && v !== a[i - 1]).join(' › ');
  return `${where} · ${c.title}`;
}
