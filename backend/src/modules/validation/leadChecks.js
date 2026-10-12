/**
 * Validation memory: what each validator has already established about a
 * business, so running a validator twice does not repeat work.
 *
 * Keyed by `leadDocId` — the same id the business has in `leads`,
 * `websiteLeads`, `whatsappLeads` and `emailLeads` — so the memory applies
 * whether a lead was validated from a saved list or from an Excel archive
 * (which has no documents of its own), and survives the lead being deleted
 * and re-scanned.
 *
 *   leadChecks/{id} = {
 *     business,
 *     email:    { status: found|none|invalid|unreachable, at, address?, reason? },
 *     whatsapp: { valid: boolean, at },
 *   }
 *
 * Why it exists: "found" and "on WhatsApp" were always remembered (the lead
 * gains an `email` / `whatsAppCheckedAt`). A *negative* email result left no
 * trace, so every run re-crawled the same dead ends first.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { leadDocId } from '../../lib/leadIdentity.js';

const COLLECTION = 'leadChecks';
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * How long a negative result is trusted before the lead is worth another
 * look. A site rarely gains a contact address overnight, but a failed fetch
 * is usually transient, so those come back sooner.
 */
export const EMAIL_RETRY_DAYS = { none: 30, invalid: 30, unreachable: 2 };

/** WhatsApp registration changes rarely; a definite answer is reused. */
export const WHATSAPP_RECHECK_DAYS = 90;

export const EMAIL_CHECK_STATUSES = ['found', 'none', 'invalid', 'unreachable'];

function millis(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts instanceof Date) return ts.getTime();
  return Number(ts) || 0;
}

/** When a negative email result stops being trusted, or `null` for `found`. */
export function emailRetryAfter(check) {
  if (!check || check.status === 'found') return null;
  const days = EMAIL_RETRY_DAYS[check.status];
  if (!days) return null;
  return new Date(millis(check.at) + days * DAY_MS);
}

/** True when an earlier email attempt is recent enough not to repeat. */
export function isEmailCheckFresh(check, now = Date.now()) {
  if (!check) return false;
  if (check.status === 'found') return true;
  const after = emailRetryAfter(check);
  return Boolean(after) && after.getTime() > now;
}

/** True when an earlier WhatsApp answer is recent enough to reuse. */
export function isWhatsAppCheckFresh(check, now = Date.now()) {
  if (!check || typeof check.valid !== 'boolean') return false;
  return millis(check.at) + WHATSAPP_RECHECK_DAYS * DAY_MS > now;
}

/** Reads the memory for [leads], as `Map<leadDocId, data>`. */
export async function getChecks(leads, { db = getFirestore() } = {}) {
  const ids = [...new Set(leads.map(leadDocId))];
  const out = new Map();
  if (!ids.length) return out;
  // getAll takes many refs; chunk to stay well inside request limits.
  for (let i = 0; i < ids.length; i += 300) {
    const slice = ids.slice(i, i + 300);
    const snaps = await db.getAll(...slice.map((id) => db.collection(COLLECTION).doc(id)));
    snaps.forEach((snap, idx) => {
      if (snap.exists) out.set(slice[idx], snap.data());
    });
  }
  return out;
}

export async function recordEmailCheck(lead, { status, address = null, reason = null }, { db = getFirestore() } = {}) {
  await db
    .collection(COLLECTION)
    .doc(leadDocId(lead))
    .set(
      {
        business: lead.business || null,
        email: { status, at: FieldValue.serverTimestamp(), address, reason },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}

export async function recordWhatsAppCheck(lead, { valid }, { db = getFirestore() } = {}) {
  await db
    .collection(COLLECTION)
    .doc(leadDocId(lead))
    .set(
      {
        business: lead.business || null,
        whatsapp: { valid: Boolean(valid), at: FieldValue.serverTimestamp() },
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}

/**
 * Adds an `emailCheck` summary to leads that still have no email, so a list
 * can show "checked, nothing found" and a validator bar knows what to
 * skip. Leads with an email, or never checked, get `emailCheck: null`.
 */
export async function attachEmailChecks(leads, { db = getFirestore() } = {}) {
  const pending = leads.filter((l) => !l.email);
  const checks = pending.length ? await getChecks(pending, { db }) : new Map();
  for (const lead of leads) {
    const check = lead.email ? null : checks.get(leadDocId(lead))?.email;
    lead.emailCheck = check
      ? {
          status: check.status,
          checkedAt: new Date(millis(check.at)).toISOString(),
          retryAfter: emailRetryAfter(check)?.toISOString() ?? null,
        }
      : null;
  }
  return leads;
}

/** Test seam. */
export const _COLLECTION = COLLECTION;
