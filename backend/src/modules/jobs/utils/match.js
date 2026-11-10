/**
 * Client-side matching of a posting against a search combination.
 *
 * Search APIs (Adzuna, Jooble) filter on the server. ATS job boards
 * (Greenhouse, Lever, Ashby, Workable) and the Remotive feed can only be read
 * whole, so they are filtered here — with the same rules for every source.
 */

import { fold } from './text.js';
import { geoCatalog } from '../geo/geoCatalog.js';
import { WORLDWIDE_CODE } from '../models/constants.js';

const ROLE_NOUNS = new Set(['developer', 'engineer', 'programmer', 'dev', 'swe', 'coder']);
const FILLER = new Set(['a', 'an', 'the', 'and', 'or', 'of', 'for', 'in', 'at', 'to', 'with', 'm', 'f', 'd', 'w', 'x']);
const SYNONYMS = { sr: 'senior', jr: 'junior', frontend: 'front end', backend: 'back end', fullstack: 'full stack' };

function tokens(text) {
  return fold(text)
    .split(' ')
    .filter(Boolean)
    .flatMap((t) => (SYNONYMS[t] ? SYNONYMS[t].split(' ') : [t]))
    .filter((t) => !FILLER.has(t));
}

/**
 * Does [jobTitle] answer the searched [queryTitle]? Every searched word must
 * appear in the job title; "developer", "engineer" and "programmer" count as
 * the same role word. A searched seniority ("senior") must be present; an
 * unsearched one is accepted ("Flutter Developer" finds "Senior Flutter
 * Developer" — dedupe handles the overlap between searches).
 */
export function titleMatches(queryTitle, jobTitle) {
  const q = tokens(queryTitle);
  if (!q.length) return true;
  const j = new Set(tokens(jobTitle));
  const jobHasRoleNoun = [...j].some((t) => ROLE_NOUNS.has(t));
  return q.every((t) => j.has(t) || (ROLE_NOUNS.has(t) && jobHasRoleNoun));
}

/** Every keyword must appear (as a word/phrase) in [text]. */
export function keywordsMatch(keywords, text) {
  const hay = ` ${fold(text)} `;
  return (keywords || []).every((k) => {
    const needle = fold(k);
    return !needle || hay.includes(` ${needle} `) || hay.includes(needle);
  });
}

/**
 * Comparison key for a city name: "New York City" == "New York", "St. Louis" ==
 * "Saint Louis". Datasets and postings spell the same place differently.
 */
export function cityKey(name) {
  return fold(name)
    .replace(/\bst\b/g, 'saint')
    .replace(/\bste\b/g, 'sainte')
    .replace(/\bmt\b/g, 'mount')
    .replace(/ city$/, '')
    .trim();
}

function includesWord(hay, needle) {
  if (!needle) return false;
  return ` ${hay} `.includes(` ${needle} `);
}

const OPEN_REMOTE = /\b(worldwide|anywhere|global|globally|international|any location|work from anywhere)\b/;

/**
 * Is a remote posting open to people in [countryCode]?
 * Unrestricted remote ("Remote", "Worldwide") is open to everyone.
 */
export function remoteOpenTo(job, countryCode) {
  const text = fold(job.locationText);
  if (!text || OPEN_REMOTE.test(text) || /^remote$/.test(text)) return true;
  const code = job.countryCode || geoCatalog.parseLocation(job.locationText).countryCode;
  if (code) return code === countryCode;
  // "Remote - Europe" / "EMEA": a region we can't place inside one country.
  return false;
}

/**
 * Does the posting belong to the searched place?
 * @param {object} job    { locationText, countryCode, state, city, workArrangement }
 * @param {object} query  see adapters/baseAdapter.js (SearchQuery)
 */
export function locationMatches(job, query) {
  const countryCode = query.country?.code;
  const worldwide = !countryCode || countryCode === WORLDWIDE_CODE;

  if (query.remoteOnly || worldwide) {
    if (job.workArrangement !== 'remote') return false;
    return worldwide ? true : remoteOpenTo(job, countryCode);
  }

  const text = fold(job.locationText);
  const parsed = job.countryCode || job.city || job.state ? job : { ...job, ...geoCatalog.parseLocation(job.locationText) };
  const jobCountry = parsed.countryCode || null;
  if (jobCountry && jobCountry !== countryCode) return false;

  if (query.city) {
    const city = cityKey(query.city);
    const named = cityKey(parsed.city) === city || includesWord(cityKey(job.locationText), city);
    if (!named) return false;
    // "Washington, DC" is not Washington state; a known, different state rules the match out.
    return !(query.state && parsed.state && fold(parsed.state) !== fold(query.state));
  }
  if (query.state) {
    const state = fold(query.state);
    if (fold(parsed.state) === state || includesWord(text, state)) return true;
    const region = geoCatalog.getRegion(countryCode, query.state);
    return Boolean(region?.code && new RegExp(`(^|,\\s*)${region.code}(\\s*,|\\s*$)`, 'i').test(String(job.locationText || '')));
  }
  if (jobCountry === countryCode) return true;
  const country = geoCatalog.getCountry(countryCode);
  return Boolean(country?.names.some((n) => includesWord(text, n)));
}

/** All the checks a client-side-filtered source applies. */
export function jobMatchesQuery(job, query) {
  return titleMatches(query.title, job.title) && keywordsMatch(query.keywords, `${job.title} ${job.description || ''}`) && locationMatches(job, query);
}
