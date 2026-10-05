/**
 * Email verification with a swappable provider. Never hard-code a paid
 * vendor through the rest of the app — `createEmailVerificationService()`
 * picks MX (built-in) or an HTTP provider from env.
 */

import dns from 'node:dns/promises';
import { EMAIL_VERIFY_RESULTS } from './constants.js';
import { normalizeEmail } from './emailDiscoveryService.js';

export class EmailVerificationService {
  async verify(_email) {
    throw new Error('EmailVerificationService.verify must be implemented');
  }
}

const DISPOSABLE_DOMAINS = new Set([
  'mailinator.com',
  'guerrillamail.com',
  '10minutemail.com',
  'tempmail.com',
  'yopmail.com',
  'trashmail.com',
  'getnada.com',
  'sharklasers.com',
]);

export function classifySyntax(email) {
  const normalized = normalizeEmail(email);
  if (!normalized) return { ok: false, reason: 'invalid_syntax' };
  const domain = normalized.split('@')[1];
  if (DISPOSABLE_DOMAINS.has(domain)) return { ok: false, reason: 'disposable', email: normalized, domain };
  return { ok: true, email: normalized, domain };
}

export class MxEmailVerificationService extends EmailVerificationService {
  async verify(email) {
    const syntax = classifySyntax(email);
    if (!syntax.ok) {
      return {
        result: syntax.reason === 'disposable' ? 'risky' : 'invalid',
        provider: 'mx',
        reason: syntax.reason,
        email: syntax.email || email,
      };
    }
    try {
      const records = await dns.resolveMx(syntax.domain);
      if (!records?.length) {
        return { result: 'invalid', provider: 'mx', reason: 'no_mx', email: syntax.email };
      }
      return { result: 'valid', provider: 'mx', reason: 'mx_found', email: syntax.email, mx: records[0]?.exchange || null };
    } catch (err) {
      const code = err.code || '';
      if (code === 'ENOTFOUND' || code === 'ENODATA') {
        return { result: 'invalid', provider: 'mx', reason: code, email: syntax.email };
      }
      return { result: 'unknown', provider: 'mx', reason: err.message || String(err), email: syntax.email };
    }
  }
}

/**
 * Generic HTTP verifier. Configure with EMAIL_VERIFICATION_URL that
 * accepts `{email}` and returns `{result: valid|invalid|risky|unknown}`.
 * Optional bearer key: EMAIL_VERIFICATION_API_KEY.
 */
export class HttpEmailVerificationService extends EmailVerificationService {
  constructor({ url, apiKey, timeoutMs = 10000 } = {}) {
    super();
    this.url = url;
    this.apiKey = apiKey;
    this.timeoutMs = timeoutMs;
  }

  async verify(email) {
    const syntax = classifySyntax(email);
    if (!syntax.ok) {
      return {
        result: syntax.reason === 'disposable' ? 'risky' : 'invalid',
        provider: 'http',
        reason: syntax.reason,
        email: syntax.email || email,
      };
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const headers = { 'Content-Type': 'application/json' };
      if (this.apiKey) headers.Authorization = `Bearer ${this.apiKey}`;
      const res = await fetch(this.url, {
        method: 'POST',
        headers,
        body: JSON.stringify({ email: syntax.email }),
        signal: controller.signal,
      });
      if (!res.ok) {
        return { result: 'unknown', provider: 'http', reason: `http_${res.status}`, email: syntax.email };
      }
      const body = await res.json().catch(() => ({}));
      const result = EMAIL_VERIFY_RESULTS.includes(body.result) ? body.result : 'unknown';
      return { result, provider: 'http', reason: body.reason || null, email: syntax.email };
    } catch (err) {
      return { result: 'unknown', provider: 'http', reason: err.message || String(err), email: syntax.email };
    } finally {
      clearTimeout(timer);
    }
  }
}

export function createEmailVerificationService() {
  const url = process.env.EMAIL_VERIFICATION_URL?.trim();
  if (url) {
    return new HttpEmailVerificationService({
      url,
      apiKey: process.env.EMAIL_VERIFICATION_API_KEY?.trim() || '',
    });
  }
  return new MxEmailVerificationService();
}
