/**
 * Validation memory: what each validator has already established about a
 * business, so running a validator twice does not repeat work.
 *
 * Keyed by `leadDocId` — the same id the business has in `leads` and
 * `whatsappLeads` — so the memory applies
 * whether a lead was validated from a saved list or from an Excel archive
 * (which has no documents of its own), and survives the lead being deleted
 * and re-scanned.
 *
 *   leadChecks/{id} = {
 *     business,
 *     whatsapp: { valid: boolean, at },
 *   }
 *
 * Why it exists: a definite "on WhatsApp" answer is reused instead of
 * checking the same number again.
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
/** WhatsApp registration changes rarely; a definite answer is reused. */
export const WHATSAPP_RECHECK_DAYS = 90;

function millis(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === 'function') return ts.toMillis();
  if (ts instanceof Date) return ts.getTime();
  return Number(ts) || 0;
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

/** Test seam. */
export const _COLLECTION = COLLECTION;
