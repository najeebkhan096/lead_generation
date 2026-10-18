/**
 * Contacting a New WhatsApp lead. Marks it Contacted for the salesman, and
 * counts it against that salesman's daily limit. Everything happens in one
 * transaction, so the limit holds even when two phones contact at once.
 *
 *   whatsappLeads/{leadId}          status, contactedAt, contactedBy (written here only)
 *   users/{uid}.dailyLeadLimit      set by an admin; DEFAULT_DAILY_LEAD_LIMIT when absent
 *   users/{uid}/contactDays/{day}   { count } — new leads this salesman contacted that day
 */
import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from './firebase.js';

// Must match DEFAULT_DAILY_LEAD_LIMIT in backend/src/modules/users/userStore.js.
export const DEFAULT_DAILY_LEAD_LIMIT = 10;

const LEADS = 'whatsappLeads';

// A day runs midnight to midnight in this zone, for every salesman.
const DAY_TIMEZONE = process.env.LEAD_DAY_TIMEZONE || 'Asia/Dubai';

/** 'YYYY-MM-DD' for [date] in [timeZone]. */
export function dayKey(date, timeZone = DAY_TIMEZONE) {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

/**
 * Marks [leadId] contacted by [uid] (`contacted: true`), or moves it back to
 * New (`false`). Throws an HttpsError when the daily limit is reached.
 */
export async function setWhatsAppLeadContacted({ uid, leadId, contacted, now = new Date(), db = getFirestore() }) {
  if (typeof leadId !== 'string' || !leadId) {
    throw new HttpsError('invalid-argument', 'leadId is required.', { code: 'BAD_LEAD' });
  }
  if (typeof contacted !== 'boolean') {
    throw new HttpsError('invalid-argument', 'contacted must be true or false.', { code: 'BAD_VALUE' });
  }

  const today = dayKey(now);
  const leadRef = db.collection(LEADS).doc(leadId);
  const userRef = db.collection('users').doc(uid);
  const counterRef = userRef.collection('contactDays').doc(today);

  return db.runTransaction(async (tx) => {
    // Transactions read everything before they write anything.
    const leadSnap = await tx.get(leadRef);
    if (!leadSnap.exists) throw new HttpsError('not-found', 'That lead no longer exists.', { code: 'NOT_FOUND' });
    const lead = leadSnap.data();
    const isNew = !lead.status || lead.status === 'lead';

    if (contacted) {
      if (!isNew) {
        if (lead.contactedBy === uid) return { contacted: true, counted: false };
        throw new HttpsError('failed-precondition', 'Another salesman has already contacted this lead.', { code: 'TAKEN' });
      }

      const user = (await tx.get(userRef)).data() ?? {};
      const limit = Number.isInteger(user.dailyLeadLimit) ? user.dailyLeadLimit : DEFAULT_DAILY_LEAD_LIMIT;
      const used = (await tx.get(counterRef)).data()?.count ?? 0;
      if (used >= limit) {
        throw new HttpsError(
          'resource-exhausted',
          `Daily limit reached: you have contacted ${used} of ${limit} new leads today.`,
          { code: 'DAILY_LIMIT', used, limit },
        );
      }

      tx.update(leadRef, { status: 'contacted', contactedAt: FieldValue.serverTimestamp(), contactedBy: uid });
      tx.set(counterRef, { count: used + 1 }, { merge: true });
      return { contacted: true, counted: true, used: used + 1, limit };
    }

    if (isNew) return { contacted: false, counted: false };
    if (lead.contactedBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the salesman who contacted this lead can move it back.', { code: 'NOT_YOURS' });
    }

    // Moving back frees today's slot only when the contact itself was today.
    const contactedDay = lead.contactedAt?.toDate ? dayKey(lead.contactedAt.toDate()) : null;
    const refund = contactedDay === today;
    const used = refund ? ((await tx.get(counterRef)).data()?.count ?? 0) : 0;

    tx.update(leadRef, { status: 'lead', contactedAt: FieldValue.delete(), contactedBy: FieldValue.delete() });
    if (refund) tx.set(counterRef, { count: Math.max(0, used - 1) }, { merge: true });
    return { contacted: false, counted: refund };
  });
}
