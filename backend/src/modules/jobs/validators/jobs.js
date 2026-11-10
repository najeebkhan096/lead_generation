/** Validation for job-related requests: list filters, status changes, applications, alerts. */

import { Problems, isObject, str, num, bool, q } from './validate.js';
import {
  EMPLOYMENT_TYPES,
  WORK_ARRANGEMENTS,
  EXPERIENCE_LEVELS,
  JOB_STATUSES,
  USER_STATES,
  APPLICATION_STAGES,
  JOB_SORTS,
} from '../models/constants.js';
import { invalid } from '../utils/errors.js';

function pickEnum(p, field, value, allowed) {
  if (value === undefined) return undefined;
  if (!allowed.includes(value)) {
    p.add(field, `must be one of: ${allowed.join(', ')}`);
    return undefined;
  }
  return value;
}

/** GET /api/jobs?… -> filters understood by jobStore.list. */
export function parseJobFilters(query) {
  const p = new Problems();
  const f = {
    countryCode: q.str(query, 'country')?.toUpperCase(),
    state: q.str(query, 'state'),
    city: q.str(query, 'city'),
    company: q.str(query, 'company'),
    q: q.str(query, 'q'),
    skills: q.list(query, 'skills'),
    experienceLevel: pickEnum(p, 'experienceLevel', q.str(query, 'experienceLevel'), EXPERIENCE_LEVELS),
    employmentType: pickEnum(p, 'employmentType', q.str(query, 'employmentType'), EMPLOYMENT_TYPES),
    workArrangement: pickEnum(p, 'workArrangement', q.str(query, 'workArrangement'), WORK_ARRANGEMENTS),
    source: q.str(query, 'source'),
    userState: pickEnum(p, 'userState', q.str(query, 'userState'), USER_STATES),
    status: pickEnum(p, 'status', q.str(query, 'status'), JOB_STATUSES),
    salaryCurrency: q.str(query, 'salaryCurrency')?.toUpperCase(),
    runId: q.str(query, 'runId'),
    sort: pickEnum(p, 'sort', q.str(query, 'sort'), Object.keys(JOB_SORTS)) || 'discovered',
    direction: q.str(query, 'direction') === 'asc' ? 'asc' : 'desc',
    limit: q.int(query, 'limit'),
    cursor: q.str(query, 'cursor'),
  };
  for (const [key, min, max] of [['salaryMin', 0, 10_000_000], ['postedWithinDays', 1, 3650], ['discoveredWithinDays', 1, 3650]]) {
    const n = q.int(query, key);
    if (n !== undefined && (n < min || n > max)) p.add(key, `must be between ${min} and ${max}`);
    else f[key] = n;
  }
  if (q.str(query, 'companyKey')) f.companyKey = q.str(query, 'companyKey');
  if (f.countryCode && !/^[A-Z]{2}$/.test(f.countryCode)) p.add('country', 'must be a 2-letter country code');
  p.throwIfAny();
  return Object.fromEntries(Object.entries(f).filter(([, v]) => v !== undefined));
}

export function parseStatusChange(body) {
  const p = new Problems();
  const status = str(p, body, 'status', { required: true, oneOf: JOB_STATUSES });
  const reason = str(p, body, 'reason', { max: 200 });
  p.throwIfAny();
  return { status, reason };
}

/** PATCH /api/jobs/:id — what a person may change on a job. */
export function parseJobPatch(body) {
  const p = new Problems();
  if (!isObject(body)) throw invalid('Body must be a JSON object');
  const out = {};
  if (body.status !== undefined) out.status = str(p, body, 'status', { oneOf: JOB_STATUSES });
  if (body.userState !== undefined) out.userState = str(p, body, 'userState', { oneOf: USER_STATES });
  if (body.notes !== undefined) out.notes = str(p, body, 'notes', { max: 2000 });
  p.throwIfAny();
  if (!Object.keys(out).length) throw invalid('Nothing to update: send status, userState or notes');
  return out;
}

export function parseIdList(body, max = 500) {
  const ids = body?.ids;
  if (!Array.isArray(ids) || !ids.length) throw invalid('ids must be a non-empty list');
  if (ids.length > max) throw invalid(`at most ${max} ids per request`);
  if (ids.some((id) => typeof id !== 'string' || !id || id.includes('/'))) throw invalid('ids must be document ids');
  return [...new Set(ids)];
}

export function parseApplication(body, { partial = false } = {}) {
  const p = new Problems();
  const out = {};
  if (!partial || body?.stage !== undefined) out.stage = str(p, body, 'stage', { required: !partial, oneOf: APPLICATION_STAGES });
  if (body?.notes !== undefined) out.notes = str(p, body, 'notes', { max: 4000, fallback: '' });
  if (body?.appliedAt !== undefined) {
    const d = body.appliedAt ? new Date(body.appliedAt) : null;
    if (d && Number.isNaN(d.getTime())) p.add('appliedAt', 'must be a date');
    out.appliedAt = d;
  }
  if (body?.followUpAt !== undefined) {
    const d = body.followUpAt ? new Date(body.followUpAt) : null;
    if (d && Number.isNaN(d.getTime())) p.add('followUpAt', 'must be a date');
    out.followUpAt = d;
  }
  if (body?.contact !== undefined) out.contact = str(p, body, 'contact', { max: 200 });
  p.throwIfAny();
  return out;
}

export function parseAlert(body, { sourceIds = [] } = {}) {
  const p = new Problems();
  if (!isObject(body)) throw invalid('Body must be a JSON object');
  const name = str(p, body, 'name', { required: true, max: 80, min: 2 });
  const f = isObject(body.filters) ? body.filters : {};
  const filters = {
    q: str(p, f, 'q', { max: 100 }),
    countryCode: str(p, f, 'countryCode', { pattern: /^[A-Za-z]{2}$/ })?.toUpperCase() ?? null,
    state: str(p, f, 'state', { max: 80 }),
    city: str(p, f, 'city', { max: 80 }),
    workArrangement: str(p, f, 'workArrangement', { oneOf: WORK_ARRANGEMENTS }),
    employmentType: str(p, f, 'employmentType', { oneOf: EMPLOYMENT_TYPES }),
    experienceLevel: str(p, f, 'experienceLevel', { oneOf: EXPERIENCE_LEVELS }),
    salaryMin: num(p, f, 'salaryMin', { min: 0, max: 10_000_000 }),
    skills: Array.isArray(f.skills) ? f.skills.map(String).slice(0, 10) : [],
    source: str(p, f, 'source', { max: 40 }),
  };
  if (filters.source && sourceIds.length && !sourceIds.includes(filters.source)) p.add('filters.source', `unknown source "${filters.source}"`);
  const out = {
    name,
    enabled: bool(p, body, 'enabled', true),
    filters,
    notify: { email: str(p, isObject(body.notify) ? body.notify : {}, 'email', { max: 200, pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ }) },
  };
  p.throwIfAny();
  return out;
}

export function parseSourceUpdate(body) {
  const p = new Problems();
  if (!isObject(body)) throw invalid('Body must be a JSON object');
  const out = {};
  if (body.enabled !== undefined) out.enabled = bool(p, body, 'enabled');
  if (body.limits !== undefined) {
    const l = isObject(body.limits) ? body.limits : {};
    out.limits = {
      perMinute: num(p, l, 'perMinute', { min: 1, max: 600, integer: true }),
      perDay: num(p, l, 'perDay', { min: 1, max: 1_000_000, integer: true }),
      maxConcurrent: num(p, l, 'maxConcurrent', { min: 1, max: 8, integer: true }),
    };
    for (const k of Object.keys(out.limits)) if (out.limits[k] == null) delete out.limits[k];
  }
  if (body.settings !== undefined) {
    const s = isObject(body.settings) ? body.settings : {};
    out.settings = {};
    if (s.boards !== undefined) {
      if (!Array.isArray(s.boards) || s.boards.length > 200) p.add('settings.boards', 'must be a list of at most 200 board tokens');
      else
        out.settings.boards = s.boards
          .map((b) => (typeof b === 'string' ? { id: b.trim() } : isObject(b) ? { id: String(b.id ?? b.token ?? '').trim(), name: b.name ? String(b.name).slice(0, 80) : null, website: b.website ? String(b.website).slice(0, 200) : null, region: b.region ? String(b.region).slice(0, 8) : null } : null))
          .filter((b) => b && /^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$/.test(b.id));
    }
    if (s.careerPages !== undefined) {
      if (!Array.isArray(s.careerPages) || s.careerPages.length > 100) p.add('settings.careerPages', 'must be a list of at most 100 pages');
      else {
        out.settings.careerPages = [];
        s.careerPages.forEach((c, i) => {
          let url = null;
          try {
            url = new URL(c?.url);
          } catch {
            /* reported below */
          }
          if (!url || !/^https?:$/.test(url.protocol)) return p.add(`settings.careerPages[${i}].url`, 'must be an http(s) URL');
          out.settings.careerPages.push({
            company: c.company ? String(c.company).slice(0, 80) : null,
            url: url.href,
            website: c.website ? String(c.website).slice(0, 200) : null,
            linkPattern: c.linkPattern ? String(c.linkPattern).slice(0, 120) : null,
            maxDetailPages: Number.isFinite(Number(c.maxDetailPages)) ? Math.min(100, Math.max(0, Number(c.maxDetailPages))) : undefined,
            render: ['auto', 'always', 'never'].includes(c.render) ? c.render : 'auto',
          });
        });
      }
    }
    const maxPages = num(p, s, 'maxPages', { min: 1, max: 10, integer: true });
    if (maxPages != null) out.settings.maxPages = maxPages;
  }
  p.throwIfAny();
  if (!Object.keys(out).length) throw invalid('Nothing to update: send enabled, limits or settings');
  return out;
}

