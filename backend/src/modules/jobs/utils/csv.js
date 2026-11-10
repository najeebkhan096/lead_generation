/**
 * CSV for exports. Quotes and newlines are escaped (RFC 4180), and a cell that
 * would be read as a formula by a spreadsheet (starts with = + - @ or a tab/CR)
 * is prefixed with an apostrophe — job titles come from the open internet.
 */

const FORMULA = /^[=+\-@\t\r]/;

export function csvCell(value) {
  if (value === null || value === undefined) return '';
  let s = value instanceof Date ? value.toISOString() : Array.isArray(value) ? value.join('; ') : String(value);
  if (FORMULA.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function csvRow(values) {
  return values.map(csvCell).join(',');
}

/** The exported columns: [header, (job) => value]. */
export const JOB_COLUMNS = [
  ['Title', (j) => j.title],
  ['Company', (j) => j.companyName],
  ['Company website', (j) => j.companyWebsite],
  ['Location', (j) => j.locationText],
  ['Country', (j) => j.country],
  ['State / Province', (j) => j.state],
  ['City', (j) => j.city],
  ['Work arrangement', (j) => j.workArrangement],
  ['Employment type', (j) => j.employmentType],
  ['Experience level', (j) => j.experienceLevel],
  ['Experience (years)', (j) => j.experienceYearsMin],
  ['Salary min', (j) => j.salaryMin],
  ['Salary max', (j) => j.salaryMax],
  ['Salary currency', (j) => j.salaryCurrency],
  ['Salary period', (j) => j.salaryPeriod],
  ['Required skills', (j) => j.requiredSkills],
  ['Preferred skills', (j) => j.preferredSkills],
  ['Posted', (j) => j.postedAt],
  ['Deadline', (j) => j.deadlineAt],
  ['Sources', (j) => j.sourceNames],
  ['Original URL', (j) => j.sourceUrl],
  ['Application URL', (j) => j.applyUrl],
  ['Status', (j) => j.status],
  ['My status', (j) => j.userState],
  ['Discovered', (j) => j.discoveredAt],
  ['Last verified', (j) => j.lastVerifiedAt],
];

export const csvHeader = () => csvRow(JOB_COLUMNS.map(([h]) => h));
export const jobCsvRow = (job) => csvRow(JOB_COLUMNS.map(([, get]) => get(job)));
