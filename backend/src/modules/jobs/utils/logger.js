/**
 * Structured logging for the Jobs module: one JSON object per line, so a log
 * shipper (or `grep scope=...`) can read it. Secrets are redacted by field
 * name and by URL query, so a key can't reach the logs by accident.
 */

import { scrub } from './errors.js';

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const SECRET_FIELD = /key|token|secret|password|authorization|credential/i;

function redact(value, depth = 0) {
  if (value == null || depth > 4) return value;
  if (typeof value === 'string') return scrub(value);
  if (value instanceof Error) return { name: value.name, message: scrub(value.message), kind: value.kind, status: value.status };
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.slice(0, 20).map((v) => redact(v, depth + 1));
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = SECRET_FIELD.test(k) ? '***' : redact(v, depth + 1);
    return out;
  }
  return value;
}

/**
 * @param {string} scope  e.g. "scan" -> logged as "jobs.scan"
 * @param {object} [opts]
 * @param {{log: Function, warn: Function, error: Function}} [opts.sink]
 * @param {string} [opts.level]
 * @param {object} [opts.base]  fields added to every line
 */
export function createLogger(scope, { sink = console, level = process.env.JOBS_LOG_LEVEL || 'info', base = {}, now = () => new Date() } = {}) {
  const threshold = LEVELS[level] ?? LEVELS.info;
  const write = (lvl, msg, fields) => {
    if (LEVELS[lvl] < threshold) return;
    const line = JSON.stringify({ ts: now().toISOString(), level: lvl, scope: `jobs.${scope}`, msg, ...redact({ ...base, ...fields }) });
    (lvl === 'error' ? sink.error : lvl === 'warn' ? sink.warn : sink.log).call(sink, line);
  };
  return {
    debug: (msg, fields) => write('debug', msg, fields),
    info: (msg, fields) => write('info', msg, fields),
    warn: (msg, fields) => write('warn', msg, fields),
    error: (msg, fields) => write('error', msg, fields),
    child: (extra) => createLogger(scope, { sink, level, base: { ...base, ...extra }, now }),
  };
}

/** A logger that drops everything — the default in unit tests. */
export const silentLogger = (() => {
  const noop = () => {};
  const l = { debug: noop, info: noop, warn: noop, error: noop };
  l.child = () => l;
  return l;
})();
