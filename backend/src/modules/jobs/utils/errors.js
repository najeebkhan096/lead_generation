/**
 * Two error families:
 *
 *  - [HttpError]   a problem with an API request (validation, not found …);
 *                  carries the status code the response should use.
 *  - [SourceError] a job source (API, ATS board, career page) misbehaved.
 *                  Never an HTTP status for our own API — the scan engine
 *                  records it against the source and carries on.
 */

export class HttpError extends Error {
  constructor(status, message, { code, details } = {}) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code || defaultCode(status);
    this.details = details;
  }
}

function defaultCode(status) {
  switch (status) {
    case 400:
      return 'BAD_REQUEST';
    case 401:
      return 'UNAUTHENTICATED';
    case 403:
      return 'FORBIDDEN';
    case 404:
      return 'NOT_FOUND';
    case 409:
      return 'CONFLICT';
    case 422:
      return 'VALIDATION_FAILED';
    case 429:
      return 'RATE_LIMITED';
    default:
      return status >= 500 ? 'INTERNAL' : 'ERROR';
  }
}

export const badRequest = (message, details) => new HttpError(400, message, { details });
export const invalid = (message, details) => new HttpError(422, message, { code: 'VALIDATION_FAILED', details });
export const notFound = (message = 'Not found') => new HttpError(404, message);
export const conflict = (message, code) => new HttpError(409, message, { code });

/**
 * kind:
 *   timeout | network      transient — retried
 *   rate_limited           429 — retried after Retry-After, then reported
 *   quota                  our own daily budget for the source is spent
 *   auth                   401/403 from an API (bad or missing key)
 *   not_found              404/410 — definitive for a single posting
 *   http_error             any other 4xx/5xx
 *   parse                  the response was not what the adapter expects
 *   blocked                a CAPTCHA / bot wall — NEVER worked around
 *   not_configured         the source needs a key/board list that isn't set
 *   disallowed             robots.txt (or an unsafe URL) forbids collecting
 */
export class SourceError extends Error {
  constructor(kind, message, { status, retryable, retryAfterMs, source, cause } = {}) {
    super(message, cause ? { cause } : undefined);
    this.name = 'SourceError';
    this.kind = kind;
    this.status = status ?? null;
    this.retryable = retryable ?? (kind === 'timeout' || kind === 'network' || kind === 'rate_limited');
    this.retryAfterMs = retryAfterMs ?? null;
    this.source = source ?? null;
  }
}

/** Errors that mean "this source is unusable for the rest of the run". */
export function isFatalForSource(err) {
  return err instanceof SourceError && ['auth', 'quota', 'not_configured', 'blocked', 'disallowed'].includes(err.kind);
}

/** What goes into a run's stats: short, free of URLs/keys. */
export function describeError(err) {
  if (err instanceof SourceError) return { kind: err.kind, status: err.status, message: scrub(err.message) };
  return { kind: 'error', status: null, message: scrub(err?.message || String(err)) };
}

/** Removes key-like query values from anything about to be logged or stored. */
export function scrub(text) {
  return String(text ?? '')
    .replace(/([?&](?:app_key|app_id|api_key|apikey|key|token|secret|access_token)=)[^&\s]+/gi, '$1***')
    .replace(/(\/api\/)[A-Za-z0-9-]{16,}/g, '$1***')
    .slice(0, 500);
}
