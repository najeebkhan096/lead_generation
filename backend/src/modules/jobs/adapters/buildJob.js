/**
 * Turns what an adapter read from its source into the one normalized job
 * shape the rest of the module uses.
 *
 * Adapters do the source-specific part (field names, pagination); everything
 * derivable from the *text* — salary, skills, experience, education,
 * responsibilities, work arrangement — is derived here, identically for all
 * sources. A value the source and the text don't state stays `null`.
 */

import { htmlToText, textOrNull, numberOrNull, dateOrNull, truncate, cleanText } from '../utils/text.js';
import {
  parseSalaryText,
  detectEmploymentType,
  detectWorkArrangement,
  detectExperienceLevel,
  extractExperience,
  extractEducation,
  parseSections,
  bulletList,
  classifySkills,
} from '../utils/extract.js';
import { canonicalUrl, isAggregatorUrl } from '../utils/normalize.js';
import { geoCatalog } from '../geo/geoCatalog.js';
import { EMPLOYMENT_TYPES, WORK_ARRANGEMENTS, SALARY_PERIODS, EXPERIENCE_LEVELS } from '../models/constants.js';

/** Keeps a stored description bounded; Firestore documents are capped at 1 MiB. */
export const MAX_DESCRIPTION_CHARS = 20_000;

const oneOf = (value, list) => (list.includes(value) ? value : null);

/**
 * @param {object} i  adapter-provided fields (see below)
 * @returns {object|null}  the normalized job, or null when it lacks a title/company/id
 */
export function buildJob(i) {
  const title = textOrNull(i.title);
  const companyName = textOrNull(i.companyName);
  const sourceJobId = textOrNull(i.sourceJobId);
  if (!title || !companyName || !sourceJobId || !i.source) return null;

  const description = cleanText(i.description != null ? i.description : htmlToText(i.descriptionHtml));
  const sections = parseSections(description);
  const skills = classifySkills(description, i.tags || []);

  // ---- location: structured fields from the source win; free text fills gaps.
  const locationText = textOrNull(i.locationText);
  const parsed = locationText ? geoCatalog.parseLocation(locationText, { countryHint: i.countryCode || null }) : {};
  const countryCode = textOrNull(i.countryCode)?.toUpperCase() || parsed.countryCode || null;
  const countryRecord = countryCode ? geoCatalog.getCountry(countryCode) : null;

  // ---- pay: structured numbers if given, else the source's pay text.
  let salary = { min: numberOrNull(i.salaryMin), max: numberOrNull(i.salaryMax), currency: textOrNull(i.salaryCurrency), period: oneOf(i.salaryPeriod, SALARY_PERIODS) };
  if (salary.min == null && salary.max == null && i.salaryText) salary = parseSalaryText(i.salaryText);
  if (salary.min != null && salary.max == null) salary.max = salary.min;
  if (salary.max != null && salary.min == null) salary.min = salary.max;
  if (salary.min == null && salary.max == null) salary = { min: null, max: null, currency: null, period: null };

  const experience = extractExperience(description);
  const workArrangement =
    oneOf(i.workArrangement, WORK_ARRANGEMENTS) ||
    detectWorkArrangement(i.workArrangementText, locationText, title, truncate(description, 600));

  const sourceUrl = canonicalUrl(i.sourceUrl) ? i.sourceUrl : null;
  const applyUrl = canonicalUrl(i.applyUrl) ? i.applyUrl : null;

  return {
    source: i.source,
    sourceJobId,
    sourceUrl,
    applyUrl,
    // Adapter-specific pointer needed to re-read the posting later (e.g. the ATS board token).
    sourceRef: i.sourceRef ?? null,
    // The apply link is "direct" when it leads to the employer/ATS, not a relay site.
    applyUrlDirect: Boolean(applyUrl) && !isAggregatorUrl(applyUrl),

    title,
    companyName,
    companyWebsite: textOrNull(i.companyWebsite),
    companyLocation: textOrNull(i.companyLocation),

    country: textOrNull(i.country) || parsed.country || countryRecord?.name || null,
    countryCode,
    state: textOrNull(i.state) || parsed.state || null,
    city: textOrNull(i.city) || parsed.city || null,
    locationText,

    salaryMin: salary.min,
    salaryMax: salary.max,
    salaryCurrency: salary.currency,
    salaryPeriod: salary.period,
    salaryIsEstimate: Boolean(i.salaryIsEstimate),

    employmentType: oneOf(i.employmentType, EMPLOYMENT_TYPES) || detectEmploymentType(i.employmentTypeText, title),
    experienceLevel: oneOf(i.experienceLevel, EXPERIENCE_LEVELS) || detectExperienceLevel(title, description),
    experienceYearsMin: numberOrNull(i.experienceYearsMin) ?? experience.years,
    experienceText: textOrNull(i.experienceText) || experience.text,
    educationText: textOrNull(i.educationText) || extractEducation(description),

    requiredSkills: skills.requiredSkills,
    preferredSkills: skills.preferredSkills,
    skillsBasis: skills.skillsBasis,

    description: truncate(description, MAX_DESCRIPTION_CHARS) || null,
    descriptionTruncatedBySource: Boolean(i.descriptionTruncatedBySource),
    responsibilities: sections.responsibilities.length ? bulletList(sections.responsibilities) : null,

    postedAt: dateOrNull(i.postedAt),
    deadlineAt: dateOrNull(i.deadlineAt),
    sourceUpdatedAt: dateOrNull(i.sourceUpdatedAt),
    workArrangement,

    recruiter: i.recruiter && Object.values(i.recruiter).some(Boolean)
      ? { name: textOrNull(i.recruiter.name), email: textOrNull(i.recruiter.email), phone: textOrNull(i.recruiter.phone), url: textOrNull(i.recruiter.url) }
      : null,

    raw: i.raw ?? null,
  };
}
