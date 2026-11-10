/**
 * The HTTP client every job-source adapter goes through.
 *
 * Request timeout, bounded body size, retry with exponential backoff and
 * jitter (network errors, timeouts, 429 and 5xx only — a 4xx is the
 * server's final answer), `Retry-After` honoured, and every failure turned
 * into a [SourceError] whose message never contains a key.
 */

import { SourceError, scrub } from './errors.js';

export const DEFAULT_USER_AGENT = 'LeadFinderBot/1.0 (+jobs-finder; job aggregation; respects robots.txt)';
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_MAX_ATTEMPTS = 3;
const DEFAULT_BASE_DELAY_MS = 600;
const DEFAULT_MAX_DELAY_MS = 20_000;
/** A server asking us to wait longer than this is not retried in-line. */
const DEFAULT_MAX_RETRY_AFTER_MS = 60_000;
const DEFAULT_MAX_BODY_BYTES = 8_000_000;

/** `Retry-After` is seconds or an HTTP date. */
export function parseRetryAfter(value, now = Date.now()) {
  if (value == null || value === '') return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);
  const at = Date.parse(value);
  return Number.isFinite(at) ? Math.max(0, at - now) : null;
}

/** Exponential backoff with jitter: attempt 1 -> ~base, 2 -> ~2x base … */
export function backoffDelay(attempt, { baseDelayMs = DEFAULT_BASE_DELAY_MS, maxDelayMs = DEFAULT_MAX_DELAY_MS, random = Math.random } = {}) {
  const exp = Math.min(maxDelayMs, baseDelayMs * 2 ** (attempt - 1));
  return Math.round(exp * (0.5 + random() * 0.5));
}

function withQuery(url, query) {
  if (!query) return url;
  const u = new URL(url);
  for (const [k, v] of Object.entries(query)) {
    if (v === undefined || v === null || v === '') continue;
    u.searchParams.set(k, String(v));
  }
  return u.toString();
}

async function readBody(res, cap) {
  const declared = Number(res.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > cap) {
    await res.body?.cancel?.().catch(() => {});
    throw new SourceError('parse', `Response too large (${declared} bytes)`, { retryable: false });
  }
  const text = await res.text();
  if (text.length > cap) throw new SourceError('parse', 'Response too large', { retryable: false });
  return text;
}

function classify(status, retryAfterMs) {
  if (status === 429) return new SourceError('rate_limited', 'HTTP 429 (rate limited)', { status, retryAfterMs, retryable: true });
  if (status === 401 || status === 403) return new SourceError('auth', `HTTP ${status} (access denied)`, { status, retryable: false });
  if (status === 404 || status === 410) return new SourceError('not_found', `HTTP ${status}`, { status, retryable: false });
  if (status >= 500) return new SourceError('http_error', `HTTP ${status}`, { status, retryable: true });
  return new SourceError('http_error', `HTTP ${status}`, { status, retryable: false });
}

/**
 * @param {object} [opts]
 * @param {typeof fetch} [opts.fetchImpl]
 * @param {(ms: number) => Promise<void>} [opts.sleep]  test seam
 */
export function createHttpClient({
  fetchImpl = globalThis.fetch,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  maxAttempts = DEFAULT_MAX_ATTEMPTS,
  baseDelayMs = DEFAULT_BASE_DELAY_MS,
  maxDelayMs = DEFAULT_MAX_DELAY_MS,
  maxRetryAfterMs = DEFAULT_MAX_RETRY_AFTER_MS,
  maxBodyBytes = DEFAULT_MAX_BODY_BYTES,
  userAgent = DEFAULT_USER_AGENT,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  random = Math.random,
  onRequest = () => {},
  onRetry = () => {},
} = {}) {
  /**
   * @returns {Promise<{status: number, headers: Headers, text: string, url: string}>}
   * @throws {SourceError}
   */
  async function request(url, { method = 'GET', headers = {}, body, query, timeoutMs: t = timeoutMs, attempts = maxAttempts } = {}) {
    const target = withQuery(url, query);
    let lastError;
    for (let attempt = 1; attempt <= attempts; attempt++) {
      onRequest({ url: scrub(target), method, attempt });
      try {
        const res = await fetchImpl(target, {
          method,
          body,
          headers: { 'user-agent': userAgent, accept: 'application/json, text/html;q=0.8, */*;q=0.5', ...headers },
          signal: AbortSignal.timeout(t),
        });
        if (res.status >= 400) {
          const err = classify(res.status, parseRetryAfter(res.headers.get('retry-after')));
          await res.body?.cancel?.().catch(() => {});
          throw err;
        }
        return { status: res.status, headers: res.headers, text: await readBody(res, maxBodyBytes), url: target };
      } catch (raw) {
        lastError = toSourceError(raw, target);
        if (!lastError.retryable || attempt === attempts) break;
        let delay = backoffDelay(attempt, { baseDelayMs, maxDelayMs, random });
        if (lastError.retryAfterMs != null) {
          if (lastError.retryAfterMs > maxRetryAfterMs) break; // asked to wait too long: report, don't block a worker
          delay = Math.max(delay, lastError.retryAfterMs);
        }
        onRetry({ url: scrub(target), attempt, delay, kind: lastError.kind });
        await sleep(delay);
      }
    }
    throw lastError;
  }

  async function getJson(url, opts) {
    const res = await request(url, opts);
    return parseJson(res.text);
  }

  async function postJson(url, payload, opts = {}) {
    const res = await request(url, {
      ...opts,
      method: 'POST',
      body: JSON.stringify(payload ?? {}),
      headers: { 'content-type': 'application/json', ...(opts.headers || {}) },
    });
    return parseJson(res.text);
  }

  const getText = async (url, opts) => (await request(url, opts)).text;

  return { request, getJson, postJson, getText };
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    throw new SourceError('parse', 'Response was not valid JSON', { retryable: false });
  }
}

function toSourceError(err, url) {
  if (err instanceof SourceError) return err;
  const timedOut = err?.name === 'TimeoutError' || err?.name === 'AbortError';
  return new SourceError(timedOut ? 'timeout' : 'network', timedOut ? 'Request timed out' : scrub(`Network error: ${err?.cause?.code || err?.message || 'unknown'}`), {
    retryable: true,
    cause: err,
  });
}
