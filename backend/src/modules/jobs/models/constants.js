/**
 * Vocabulary shared by the whole Jobs Finder module: collection names and
 * the closed sets of values stored on documents. Anything user-facing is
 * validated against these lists (see validators/).
 */

export const COLLECTIONS = Object.freeze({
  jobs: 'jobs',
  companies: 'companies',
  searches: 'job_searches',
  sources: 'job_sources',
  scanRuns: 'job_scan_runs',
  applications: 'job_applications',
  alerts: 'job_alerts',
  queue: 'job_search_queue',
  // Lookup documents used for duplicate detection (see services/dedupe.js).
  keys: 'job_keys',
});

/** Sub-collection of `jobs/{id}` holding the original source payloads. */
export const RAW_SUBCOLLECTION = 'raw';

/** Is the posting still open? Independent of what the user did with it. */
export const JOB_STATUSES = Object.freeze(['active', 'expired', 'unavailable']);

/** The user's triage state of a job (kept on the job so lists can filter on it). */
export const USER_STATES = Object.freeze(['new', 'saved', 'applied', 'rejected', 'withdrawn']);

/** The application pipeline, in order. */
export const APPLICATION_STAGES = Object.freeze([
  'saved',
  'applied',
  'assessment',
  'interview',
  'offered',
  'rejected',
  'withdrawn',
]);

/** Pipeline stage -> the coarse `userState` kept on the job document. */
export function userStateForStage(stage) {
  switch (stage) {
    case 'saved':
      return 'saved';
    case 'applied':
    case 'assessment':
    case 'interview':
    case 'offered':
      return 'applied';
    case 'rejected':
      return 'rejected';
    case 'withdrawn':
      return 'withdrawn';
    default:
      return 'new';
  }
}

export const EMPLOYMENT_TYPES = Object.freeze([
  'full_time',
  'part_time',
  'contract',
  'temporary',
  'internship',
  'freelance',
  'permanent',
]);

export const WORK_ARRANGEMENTS = Object.freeze(['remote', 'hybrid', 'onsite']);
export const EXPERIENCE_LEVELS = Object.freeze(['entry', 'mid', 'senior', 'lead', 'executive']);
export const SALARY_PERIODS = Object.freeze(['hour', 'day', 'week', 'month', 'year']);

export const RUN_STATUSES = Object.freeze([
  'queued',
  'running',
  'paused',
  'stopping',
  'completed',
  'stopped',
  'failed',
  'interrupted',
]);
/** A run in one of these states still owns work (an interrupted run waits to be resumed). */
export const ACTIVE_RUN_STATUSES = Object.freeze(['queued', 'running', 'paused', 'stopping', 'interrupted']);

export const TASK_STATUSES = Object.freeze(['pending', 'running', 'done', 'failed', 'skipped']);

/** Worldwide / Remote pseudo-country: no regions, search text is "Remote". */
export const WORLDWIDE_CODE = 'WW';

/** Source authority when two sources disagree about a field: higher wins. */
export const SOURCE_PRIORITY = Object.freeze({
  career_page: 50,
  greenhouse: 40,
  lever: 40,
  ashby: 40,
  workable: 40,
  adzuna: 20,
  jooble: 20,
  remotive: 20,
});

export const JOB_SORTS = Object.freeze({
  discovered: { field: 'discoveredAt', label: 'Newest discovered' },
  posted: { field: 'postedAt', label: 'Newest posted' },
  updated: { field: 'updatedAt', label: 'Recently updated' },
});
