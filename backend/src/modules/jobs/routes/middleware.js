/**
 * Express middleware for /api/jobs: async error forwarding, request logging,
 * rate limiting, optional authentication, and the one place errors become
 * HTTP responses.
 */

import { HttpError, SourceError, scrub } from '../utils/errors.js';
import { getFirestore } from '../../../firebase/admin.js';
import { requireApprovedUser } from '../../../middleware/firebaseAuth.js';

export const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Fixed-window limiter per client address. In-memory: enough for one server. */
export function rateLimit({ windowMs = 60_000, max = 240, now = Date.now, name = 'api' } = {}) {
  const hits = new Map(); // ip -> { count, resetAt }
  let sweptAt = now();
  return (req, res, next) => {
    const t = now();
    if (t - sweptAt > windowMs * 2) {
      for (const [k, v] of hits) if (v.resetAt <= t) hits.delete(k);
      sweptAt = t;
    }
    const key = req.ip || req.socket?.remoteAddress || 'unknown';
    let entry = hits.get(key);
    if (!entry || entry.resetAt <= t) {
      entry = { count: 0, resetAt: t + windowMs };
      hits.set(key, entry);
    }
    entry.count += 1;
    res.setHeader('RateLimit-Limit', String(max));
    res.setHeader('RateLimit-Remaining', String(Math.max(0, max - entry.count)));
    res.setHeader('RateLimit-Reset', String(Math.ceil((entry.resetAt - t) / 1000)));
    if (entry.count > max) {
      res.setHeader('Retry-After', String(Math.ceil((entry.resetAt - t) / 1000)));
      return next(new HttpError(429, `Too many ${name} requests; try again in ${Math.ceil((entry.resetAt - t) / 1000)}s`, { code: 'RATE_LIMITED' }));
    }
    return next();
  };
}

/**
 * Authentication, consistent with the rest of the API: nothing today (the web
 * admin console has no sign-in), but the module can require a Firebase ID
 * token of an approved account with JOBS_REQUIRE_AUTH=true — and then only
 * `admin` accounts may change anything. Flip it on once the console signs in.
 */
export function jobsAuth({ required = process.env.JOBS_REQUIRE_AUTH === 'true', verify = requireApprovedUser, roleOf = defaultRoleOf } = {}) {
  if (!required) return (_req, _res, next) => next();
  return (req, res, next) =>
    verify(req, res, async (err) => {
      if (err) return next(err);
      if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') return next();
      try {
        if ((await roleOf(req.uid)) !== 'admin') return next(new HttpError(403, 'Only admin accounts can change Jobs Finder data', { code: 'FORBIDDEN' }));
        return next();
      } catch (e) {
        return next(e);
      }
    });
}

const roleCache = new Map();
async function defaultRoleOf(uid) {
  const hit = roleCache.get(uid);
  if (hit && hit.expires > Date.now()) return hit.role;
  const snap = await getFirestore().collection('users').doc(uid).get();
  const role = snap.exists ? snap.data().role : null;
  roleCache.set(uid, { role, expires: Date.now() + 60_000 });
  return role;
}

export function requestLogger(log) {
  return (req, res, next) => {
    const started = Date.now();
    res.on('finish', () => {
      if (req.path === '/scans/active' || (req.method === 'GET' && res.statusCode < 400 && req.path.endsWith('/progress'))) return; // polled constantly
      log.info('request', { method: req.method, path: scrub(req.originalUrl.split('?')[0]), status: res.statusCode, ms: Date.now() - started });
    });
    next();
  };
}

/** The single place errors become responses. */
export function errorHandler(log) {
  // eslint-disable-next-line no-unused-vars
  return (err, req, res, _next) => {
    if (err instanceof HttpError || (err?.status && err.status < 500 && !(err instanceof SourceError))) {
      return res.status(err.status).json({ error: err.message, code: err.code || 'ERROR', details: err.details });
    }
    if (err?.status === 503) return res.status(503).json({ error: err.message, code: 'UNAVAILABLE' });
    if (err instanceof SyntaxError && 'body' in err) return res.status(400).json({ error: 'Request body is not valid JSON', code: 'BAD_REQUEST' });
    log.error('unhandled error', { method: req.method, path: req.path, error: err });
    return res.status(500).json({ error: 'Internal error', code: 'INTERNAL' });
  };
}
