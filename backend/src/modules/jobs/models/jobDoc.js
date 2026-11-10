/**
 * The stored shape of a job, and the two pure functions that produce it:
 * [buildNewDoc] for a first sighting and [mergeDoc] for a later one.
 *
 * Merge policy (a posting found again, here or on another source):
 *   - never erase: a field the new sighting doesn't know keeps its stored value;
 *   - on conflict the more authoritative source wins (employer ATS > aggregator);
 *   - skills are unioned; the fuller, non-truncated description wins;
 *   - the sighting's source is added to `sources` (first/last seen per source);
 *   - discovery history (`discoveredAt`, `discoveredBy`, per-source `firstSeenAt`)
 *     is never overwritten; `lastVerifiedAt` moves forward.
 */

import { SOURCE_PRIORITY } from './constants.js';
import {
  fingerprintOf,
  companyKey,
  titleKey,
  locationKey,
  applyUrlKey,
  descriptionSignature,
  hashText,
} from '../utils/normalize.js';
import { annualApprox } from '../utils/extract.js';
import { truncate } from '../utils/text.js';
import { toDate, toMillis } from '../services/firestoreUtil.js';

export const MAX_SOURCES_PER_JOB = 12;
const PREVIEW_CHARS = 300;

const priorityOf = (source) => SOURCE_PRIORITY[source] ?? 10;
const isEmpty = (v) => v === null || v === undefined || v === '' || (Array.isArray(v) && v.length === 0);

/** The fields whose change makes a re-sighting an "update" rather than a "duplicate". */
function contentHash(doc) {
  return hashText(
    JSON.stringify([
      doc.title, doc.companyName, doc.locationText, doc.countryCode, doc.state, doc.city,
      doc.salaryMin, doc.salaryMax, doc.salaryCurrency, doc.salaryPeriod,
      doc.employmentType, doc.workArrangement, doc.experienceLevel, doc.experienceYearsMin,
      [...(doc.requiredSkills || [])].sort(), [...(doc.preferredSkills || [])].sort(),
      hashText(doc.description || '', 16), toMillis(doc.postedAt), toMillis(doc.deadlineAt), doc.applyUrl,
    ]),
    24,
  );
}

function sourceEntry(job, now, previous) {
  return {
    source: job.source,
    sourceJobId: String(job.sourceJobId),
    sourceUrl: job.sourceUrl ?? previous?.sourceUrl ?? null,
    applyUrl: job.applyUrl ?? previous?.applyUrl ?? null,
    applyUrlDirect: job.applyUrl ? Boolean(job.applyUrlDirect) : Boolean(previous?.applyUrlDirect),
    sourceRef: job.sourceRef ?? previous?.sourceRef ?? null,
    firstSeenAt: previous?.firstSeenAt ?? now,
    lastSeenAt: now,
    missedChecks: 0,
    lastCheckedAt: previous?.lastCheckedAt ?? null,
  };
}

/** Top-level links derived from the per-source entries: best original URL and best direct apply URL. */
function linksFrom(sources, primarySource) {
  const byPriority = [...sources].sort((a, b) => priorityOf(b.source) - priorityOf(a.source));
  const primary = sources.find((s) => s.source === primarySource) || byPriority[0];
  const direct = byPriority.find((s) => s.applyUrl && s.applyUrlDirect);
  return { sourceUrl: primary?.sourceUrl ?? byPriority.find((s) => s.sourceUrl)?.sourceUrl ?? null, applyUrl: direct?.applyUrl ?? null };
}

function derived(doc, job) {
  const fields = {
    fingerprint: fingerprintOf(doc),
    companyKey: companyKey(doc.companyName),
    titleKey: titleKey(doc.title),
    locationKey: locationKey(doc),
    salaryMinAnnual: annualApprox(doc.salaryMin, doc.salaryPeriod),
    salaryMaxAnnual: annualApprox(doc.salaryMax, doc.salaryPeriod),
    descriptionPreview: doc.description ? truncate(doc.description.replace(/\s+/g, ' '), PREVIEW_CHARS) : null,
    descSig: descriptionSignature(doc.description) ?? doc.descSig ?? null,
  };
  fields.sortAt = doc.postedAt || doc.discoveredAt;
  return { ...doc, ...fields, primaryApplyKey: applyUrlKey(doc.applyUrl) };
}

/**
 * @param {object} job  normalized job (adapters/buildJob.js)
 * @param {{runId?: string, searchId?: string}} ctx
 */
export function buildNewDoc(job, ctx, now) {
  const entry = sourceEntry(job, now, null);
  const base = {
    title: job.title,
    companyName: job.companyName,
    companyWebsite: job.companyWebsite ?? null,
    companyLocation: job.companyLocation ?? null,
    country: job.country ?? null,
    countryCode: job.countryCode ?? null,
    state: job.state ?? null,
    city: job.city ?? null,
    locationText: job.locationText ?? null,
    salaryMin: job.salaryMin ?? null,
    salaryMax: job.salaryMax ?? null,
    salaryCurrency: job.salaryCurrency ?? null,
    salaryPeriod: job.salaryPeriod ?? null,
    salaryIsEstimate: Boolean(job.salaryIsEstimate),
    employmentType: job.employmentType ?? null,
    experienceLevel: job.experienceLevel ?? null,
    experienceYearsMin: job.experienceYearsMin ?? null,
    experienceText: job.experienceText ?? null,
    educationText: job.educationText ?? null,
    requiredSkills: job.requiredSkills || [],
    preferredSkills: job.preferredSkills || [],
    skillsBasis: job.skillsBasis ?? null,
    description: job.description ?? null,
    descriptionTruncatedBySource: Boolean(job.descriptionTruncatedBySource),
    responsibilities: job.responsibilities ?? null,
    postedAt: job.postedAt ?? null,
    deadlineAt: job.deadlineAt ?? null,
    workArrangement: job.workArrangement ?? null,
    recruiter: job.recruiter ?? null,

    primarySource: job.source,
    sources: [entry],
    sourceNames: [job.source],
    ...linksFrom([entry], job.source),

    status: 'active',
    statusSource: 'scan',
    statusReason: null,
    statusChangedAt: now,
    userState: 'new',
    applicationStage: null,

    discoveredAt: now,
    discoveredBy: { runId: ctx.runId ?? null, searchId: ctx.searchId ?? null },
    lastVerifiedAt: now,
    lastRunId: ctx.runId ?? null,
    seenCount: 1,
    searchIds: ctx.searchId ? [ctx.searchId] : [],
    createdAt: now,
    updatedAt: now,
  };
  const doc = derived(base, job);
  doc.contentHash = contentHash(doc);
  return doc;
}

const union = (a, b) => [...new Set([...(a || []), ...(b || [])])];

/**
 * @returns {{doc: object, outcome: 'updated'|'duplicate', newSource: boolean}}
 */
export function mergeDoc(existing, job, ctx, now) {
  const e = { ...existing, discoveredAt: toDate(existing.discoveredAt), postedAt: toDate(existing.postedAt), deadlineAt: toDate(existing.deadlineAt) };
  const higher = priorityOf(job.source) >= priorityOf(e.primarySource);
  const pick = (field) => {
    const n = job[field];
    if (isEmpty(n)) return e[field] ?? null;
    if (isEmpty(e[field])) return n;
    return higher ? n : e[field];
  };

  // Description: the fuller, non-truncated text wins; otherwise the more authoritative source.
  let description = e.description ?? null;
  let truncatedBySource = Boolean(e.descriptionTruncatedBySource);
  if (!isEmpty(job.description)) {
    const incomingBetter =
      isEmpty(description) ||
      (truncatedBySource && !job.descriptionTruncatedBySource) ||
      (truncatedBySource === Boolean(job.descriptionTruncatedBySource) && (higher || job.description.length > description.length * 1.5));
    if (incomingBetter) {
      description = job.description;
      truncatedBySource = Boolean(job.descriptionTruncatedBySource);
    }
  }

  const prevEntry = (e.sources || []).find((s) => s.source === job.source && s.sourceJobId === String(job.sourceJobId));
  const newSource = !prevEntry;
  const entry = sourceEntry(job, now, prevEntry);
  let sources = prevEntry
    ? e.sources.map((s) => (s === prevEntry ? entry : s))
    : [...(e.sources || []), entry];
  if (sources.length > MAX_SOURCES_PER_JOB) {
    // Keep the most authoritative / most recently seen ones.
    sources = [...sources].sort((a, b) => priorityOf(b.source) - priorityOf(a.source) || toMillis(b.lastSeenAt) - toMillis(a.lastSeenAt)).slice(0, MAX_SOURCES_PER_JOB);
  }
  const primarySource = higher ? job.source : e.primarySource;

  const merged = {
    ...e,
    title: pick('title'),
    companyName: pick('companyName'),
    companyWebsite: pick('companyWebsite'),
    companyLocation: pick('companyLocation'),
    country: pick('country'),
    countryCode: pick('countryCode'),
    state: pick('state'),
    city: pick('city'),
    locationText: pick('locationText'),
    salaryMin: isEmpty(job.salaryMin) ? e.salaryMin ?? null : (isEmpty(e.salaryMin) || higher ? job.salaryMin : e.salaryMin),
    salaryMax: isEmpty(job.salaryMax) ? e.salaryMax ?? null : (isEmpty(e.salaryMax) || higher ? job.salaryMax : e.salaryMax),
    salaryCurrency: pick('salaryCurrency'),
    salaryPeriod: pick('salaryPeriod'),
    employmentType: pick('employmentType'),
    experienceLevel: pick('experienceLevel'),
    experienceYearsMin: pick('experienceYearsMin'),
    experienceText: pick('experienceText'),
    educationText: pick('educationText'),
    requiredSkills: union(e.requiredSkills, job.requiredSkills),
    preferredSkills: union(e.preferredSkills, job.preferredSkills).filter((s) => !union(e.requiredSkills, job.requiredSkills).includes(s)),
    skillsBasis: pick('skillsBasis'),
    description,
    descriptionTruncatedBySource: truncatedBySource,
    responsibilities: pick('responsibilities'),
    postedAt: e.postedAt && job.postedAt ? new Date(Math.min(e.postedAt.getTime(), job.postedAt.getTime())) : e.postedAt || job.postedAt || null,
    deadlineAt: pick('deadlineAt'),
    workArrangement: pick('workArrangement'),
    recruiter: pick('recruiter'),

    primarySource,
    sources,
    sourceNames: union(e.sourceNames, [job.source]),
    ...linksFrom(sources, primarySource),

    lastVerifiedAt: now,
    lastRunId: ctx.runId ?? e.lastRunId ?? null,
    seenCount: (e.seenCount || 0) + 1,
    searchIds: union(e.searchIds, ctx.searchId ? [ctx.searchId] : []).slice(-20),
    updatedAt: now,
  };

  // Seen again by a source: a posting we had marked gone by scan is open after all.
  if (e.status !== 'active' && e.statusSource !== 'manual') {
    merged.status = 'active';
    merged.statusSource = 'scan';
    merged.statusReason = 'reappeared';
    merged.statusChangedAt = now;
  }

  const doc = derived(merged, job);
  doc.contentHash = contentHash(doc);
  const changed = doc.contentHash !== e.contentHash || newSource || (merged.status !== e.status);
  return { doc, outcome: changed ? 'updated' : 'duplicate', newSource };
}

/** Cap for the original payload kept under jobs/{id}/raw/{source}. */
export const MAX_RAW_BYTES = 100_000;

export function rawPayload(job, now) {
  let payload = job.raw ?? null;
  let truncated = false;
  const json = payload == null ? '' : JSON.stringify(payload);
  if (json.length > MAX_RAW_BYTES) {
    payload = { truncated: true, preview: json.slice(0, 2000) };
    truncated = true;
  }
  return { source: job.source, sourceJobId: String(job.sourceJobId), payload, truncated, capturedAt: now };
}
