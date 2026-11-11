/**
 * Is an address worth sending to? Syntax, disposable-domain and MX checks —
 * all local, no third-party service. The address is never contacted.
 */

import dns from 'node:dns/promises';
import { normalizeEmail, isValidBusinessEmail } from '../../website/emailExtraction.js';

const DISPOSABLE_DOMAINS = new Set([
  'mailinator.com', 'guerrillamail.com', '10minutemail.com', 'tempmail.com',
  'yopmail.com', 'trashmail.com', 'getnada.com', 'sharklasers.com',
]);

export function classifySyntax(email) {
  const normalized = normalizeEmail(email);
  if (!normalized || !isValidBusinessEmail(normalized)) return { ok: false, reason: 'invalid_syntax' };
  const domain = normalized.split('@')[1];
  if (DISPOSABLE_DOMAINS.has(domain)) return { ok: false, reason: 'disposable', email: normalized, domain };
  return { ok: true, email: normalized, domain };
}

/** `{result: 'valid'|'invalid'|'risky'|'unknown', reason, email}` */
export async function verifyEmailMx(email, { resolveMx = dns.resolveMx } = {}) {
  const syntax = classifySyntax(email);
  if (!syntax.ok) {
    return {
      result: syntax.reason === 'disposable' ? 'risky' : 'invalid',
      reason: syntax.reason,
      email: syntax.email || email,
    };
  }
  try {
    const records = await resolveMx(syntax.domain);
    if (!records?.length) return { result: 'invalid', reason: 'no_mx', email: syntax.email };
    return { result: 'valid', reason: 'mx_found', email: syntax.email };
  } catch (err) {
    const code = err.code || '';
    if (code === 'ENOTFOUND' || code === 'ENODATA') return { result: 'invalid', reason: code, email: syntax.email };
    return { result: 'unknown', reason: err.message || String(err), email: syntax.email };
  }
}
