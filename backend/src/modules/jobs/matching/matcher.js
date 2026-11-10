/**
 * Candidate ↔ job matching — the architecture for the future CV matcher.
 *
 * Deliberately NOT part of scanning: no scan, ingestion or listing calls
 * this. It runs only when someone asks (`POST /api/jobs/:id/match`), so
 * nothing here costs money per scan.
 *
 * A *provider* turns (candidate profile, job) into a result of this shape:
 *
 *   {
 *     provider, version,
 *     score:            0–100,
 *     matchingSkills:   string[],
 *     missingSkills:    string[],
 *     experience:       { requiredYears, candidateYears, compatible: true|false|null },
 *     relevantRequirements: string[],   // the job's own requirement lines that matched
 *     suggestions:      string[],       // what to add or emphasise in the CV
 *   }
 *
 * The built-in provider (`keyword`) is deterministic and local: skill overlap
 * and years of experience. To add an AI provider, implement `{ id, match }`
 * and register it with [createMatcher]'s `providers`; set JOBS_MATCH_PROVIDER
 * to choose it. Nothing else changes. (No AI provider ships today.)
 */

import { extractSkills, extractExperience, parseSections } from '../utils/extract.js';
import { fold } from '../utils/text.js';
import { invalid } from '../utils/errors.js';

export const MATCH_SCHEMA_VERSION = 1;

/** A candidate profile from CV text: skills mentioned and years of experience stated. */
export function profileFromCv(cvText) {
  const text = String(cvText || '');
  const years = [...text.matchAll(/(\d{1,2})\s*\+?\s*(?:years?|yrs?)\b/gi)].map((m) => Number(m[1])).filter((n) => n > 0 && n < 50);
  return { skills: extractSkills(text), years: years.length ? Math.max(...years) : extractExperience(text).years ?? null };
}

const keywordProvider = {
  id: 'keyword',
  version: 1,
  async match(profile, job) {
    const required = job.requiredSkills || [];
    const preferred = job.preferredSkills || [];
    const have = new Set(profile.skills.map((s) => s.toLowerCase()));
    const matchingSkills = required.filter((s) => have.has(s.toLowerCase()));
    const missingSkills = required.filter((s) => !have.has(s.toLowerCase()));
    const preferredHit = preferred.filter((s) => have.has(s.toLowerCase()));

    const requiredYears = job.experienceYearsMin ?? null;
    const compatible = requiredYears == null || profile.years == null ? null : profile.years >= requiredYears;

    // Skills carry the score; experience adjusts it; preferred skills are a small bonus.
    let score;
    if (required.length) score = (matchingSkills.length / required.length) * 85;
    else score = profile.skills.length ? 50 : 0;
    if (preferred.length) score += (preferredHit.length / preferred.length) * 10;
    if (compatible === true) score += 5;
    if (compatible === false) score -= 15;

    const sections = parseSections(job.description || '');
    const matchedNames = matchingSkills.map(fold);
    const relevantRequirements = sections.required.filter((line) => matchedNames.some((n) => fold(line).includes(n))).slice(0, 8);

    const suggestions = [];
    for (const s of missingSkills.slice(0, 6)) suggestions.push(`Add evidence of ${s} if you have it — the posting lists it as required.`);
    if (compatible === false) suggestions.push(`The posting asks for ${requiredYears}+ years of experience; make the length and depth of your relevant experience explicit.`);
    if (!profile.skills.length) suggestions.push('No known skills were found in the CV text — check that it was pasted as plain text.');

    return {
      score: Math.max(0, Math.min(100, Math.round(score))),
      matchingSkills,
      missingSkills,
      experience: { requiredYears, candidateYears: profile.years, compatible },
      relevantRequirements,
      suggestions,
    };
  },
};

/** @param {{providers?: object[], defaultProvider?: string}} [opts] */
export function createMatcher({ providers = [keywordProvider], defaultProvider = process.env.JOBS_MATCH_PROVIDER || 'keyword' } = {}) {
  const byId = new Map(providers.map((p) => [p.id, p]));
  return {
    providerIds: () => [...byId.keys()],

    async match(cvText, job, { provider = defaultProvider } = {}) {
      if (!String(cvText || '').trim()) throw invalid('cvText is required');
      if (String(cvText).length > 60_000) throw invalid('cvText is too long (60,000 characters at most)');
      const p = byId.get(provider);
      if (!p) throw invalid(`Unknown match provider "${provider}"`);
      const result = await p.match(profileFromCv(cvText), job);
      return { provider: p.id, version: MATCH_SCHEMA_VERSION, ...result };
    },
  };
}
