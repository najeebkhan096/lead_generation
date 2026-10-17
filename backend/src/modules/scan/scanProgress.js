/**
 * Saving and restoring a scan's progress at the level of single cities and
 * businesses, so a scan that runs for many hours survives a restart, a crash or
 * a pause without redoing work: a Resume skips the cities already covered and
 * does not read a business twice.
 */

import { placeIdFromHref } from '../../lib/placeId.js';

/** state -> names of its covered cities (only states with any). */
export function completedCitiesFromStates(stateRecs) {
  const out = {};
  for (const rec of stateRecs || []) {
    if (rec.covered?.length) out[rec.state] = [...rec.covered];
  }
  return out;
}

/** The place ids of businesses already in a workbook's leads (from their Maps link). */
export function placeIdsFromLeads(leads) {
  const ids = new Set();
  for (const lead of leads || []) {
    const id = placeIdFromHref(lead?.mapsUrl);
    if (id) ids.add(id);
  }
  return ids;
}

/**
 * Marks the cities a previous run already covered, so this run only does the
 * rest. Mutates the state records.
 * @param {object[]} stateRecs
 * @param {Record<string,string[]>} completedCities
 * @param {Record<string,object[]>} [seedLeadsByState] leads already collected, for the counts
 */
export function applyResumeProgress(stateRecs, completedCities = {}, seedLeadsByState = {}) {
  let restored = 0;
  for (const rec of stateRecs) {
    const done = new Set((completedCities[rec.state] || []).filter((c) => rec.cities.includes(c)));
    if (done.size) {
      rec.covered = rec.cities.filter((c) => done.has(c));
      rec.pending = rec.cities.filter((c) => !done.has(c));
      restored += done.size;
    }
    rec.leadsCollected = seedLeadsByState[rec.state]?.length || 0;
  }
  return restored;
}

/** Whether a checkpoint is due: every `everyMs`, or every `everyCities` cities, whichever comes first. */
export function checkpointDue({ now, lastAt, citiesSince }, { everyMs = 10 * 60 * 1000, everyCities = 40 } = {}) {
  return citiesSince > 0 && (now - lastAt >= everyMs || citiesSince >= everyCities);
}
