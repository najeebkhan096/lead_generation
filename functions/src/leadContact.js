/**
 * Contacting a New WhatsApp lead. Marks it Contacted for the salesman, and
 * counts it against that salesman's daily limit. Everything happens in one
 * transaction, so the limit holds even when two phones contact at once.
 *
 *   whatsappLeads/{leadId}          1-star leads: status, contactedAt, contactedBy (written here only)
 *   websiteLeads/{leadId}           no-website leads: the same three fields (written here only)
 *   users/{uid}.dailyLeadLimit      set by an admin; DEFAULT_DAILY_LEAD_LIMIT when absent
 *   users/{uid}/contactDays/{day}   { count } — new leads this salesman contacted that day
 *
 * ONE limit covers both kinds of lead: a salesman may contact `dailyLeadLimit`
 * new leads a day in total, whether 1-star or no-website. The count is every
 * lead of either kind they contacted since the day began (see `contactedToday`).
 */
import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from './firebase.js';

// Must match DEFAULT_DAILY_LEAD_LIMIT in backend/src/modules/users/userStore.js.
export const DEFAULT_DAILY_LEAD_LIMIT = 10;

const LEADS = 'whatsappLeads';
const WEBSITE_LEADS = 'websiteLeads';
const DEAL_DONE = 'dealDone';

// A day runs midnight to midnight in this zone, for every salesman. Qatar, the
// zone the team's clocks and the admin console show, so "today" matches them.
const DAY_TIMEZONE = process.env.LEAD_DAY_TIMEZONE || 'Asia/Qatar';

/** 'YYYY-MM-DD' for [date] in [timeZone]. */
export function dayKey(date, timeZone = DAY_TIMEZONE) {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

/** The instant [timeZone]'s day [day] ('YYYY-MM-DD') begins: its midnight. */
export function dayStart(day, timeZone = DAY_TIMEZONE) {
  const [y, m, d] = day.split('-').map(Number);
  const asUtc = Date.UTC(y, m - 1, d);
  return new Date(asUtc - zoneOffsetMs(new Date(asUtc), timeZone));
}

/** How far ahead of UTC [timeZone] is at [date], in milliseconds. */
function zoneOffsetMs(date, timeZone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
      hour: 'numeric', minute: 'numeric', second: 'numeric',
    }).formatToParts(date).map((p) => [p.type, Number(p.value)]),
  );
  const local = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return local - Math.floor(date.getTime() / 1000) * 1000;
}

/**
 * The queries that count what [uid] has contacted since [day] began, one per
 * kind of lead. Both match a composite index (equality fields, then
 * `contactedAt` newest first); the order does not change the count.
 */
function contactedToday(db, uid, day) {
  const since = dayStart(day);
  return [
    db.collection(LEADS)
      .where('sourceType', '==', 'review')
      .where('contactedBy', '==', uid)
      .where('contactedAt', '>=', since)
      .orderBy('contactedAt', 'desc'),
    db.collection(WEBSITE_LEADS)
      .where('contactedBy', '==', uid)
      .where('contactedAt', '>=', since)
      .orderBy('contactedAt', 'desc'),
  ];
}

/**
 * Marks [leadId] of [collection] contacted by [uid] (`contacted: true`), or
 * moves it back to New (`false`). Throws an HttpsError when the daily limit is
 * reached.
 *
 * The limit counts the leads this salesman has contacted today — of either
 * kind, the same leads the app lists — so the two cannot disagree.
 * `users/{uid}/contactDays/{day}` is still read and written in the same
 * transaction: two contacts at once both touch it, so one of them retries and
 * sees the other's lead.
 */
async function contactLeadIn(collection, { uid, leadId, contacted, now = new Date(), db = getFirestore() }) {
  if (typeof leadId !== 'string' || !leadId) {
    throw new HttpsError('invalid-argument', 'leadId is required.', { code: 'BAD_LEAD' });
  }
  if (typeof contacted !== 'boolean') {
    throw new HttpsError('invalid-argument', 'contacted must be true or false.', { code: 'BAD_VALUE' });
  }

  const today = dayKey(now);
  const leadRef = db.collection(collection).doc(leadId);
  const userRef = db.collection('users').doc(uid);
  const counterRef = userRef.collection('contactDays').doc(today);
  const countQueries = contactedToday(db, uid, today);

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
      // A no-website lead is only on the salesman's list once its number was
      // confirmed on WhatsApp; never mark one that was not.
      if (collection === WEBSITE_LEADS && lead.hasWhatsApp !== true) {
        throw new HttpsError('failed-precondition', 'This lead has not been verified on WhatsApp.', { code: 'NOT_VERIFIED' });
      }

      const user = (await tx.get(userRef)).data() ?? {};
      const limit = Number.isInteger(user.dailyLeadLimit) ? user.dailyLeadLimit : DEFAULT_DAILY_LEAD_LIMIT;
      await tx.get(counterRef);
      let used = 0;
      for (const query of countQueries) used += (await tx.get(query)).size;
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
    if (lead.status === DEAL_DONE) {
      throw new HttpsError('failed-precondition', 'This is a done deal. Reopen it before moving it back to New.', { code: 'DEAL_DONE' });
    }

    // Moving back frees a slot only when the contact itself was today; the count above no longer needs a refund.
    const contactedDay = lead.contactedAt?.toDate ? dayKey(lead.contactedAt.toDate()) : null;
    tx.update(leadRef, { status: 'lead', contactedAt: FieldValue.delete(), contactedBy: FieldValue.delete() });
    return { contacted: false, counted: contactedDay === today };
  });
}

/** Contacts a 1-star WhatsApp lead (`whatsappLeads`), within the shared daily limit. */
export const setWhatsAppLeadContacted = (args) => contactLeadIn(LEADS, args);

/** Contacts a no-website lead (`websiteLeads`), within the shared daily limit. */
export const setWebsiteLeadContacted = (args) => contactLeadIn(WEBSITE_LEADS, args);

/**
 * Marks a lead this salesman contacted as a deal done (`done: true`), or moves
 * it back to Contacted (`false`). Only the salesman who contacted the lead can
 * do either, and only a Contacted lead can become a deal.
 *
 *   whatsappLeads/{leadId}.status     contacted <-> dealDone
 *   whatsappLeads/{leadId}.dealDoneAt  set when it becomes a deal, removed on reopen
 */
export async function setWhatsAppLeadDealDone({ uid, leadId, done, db = getFirestore() }) {
  if (typeof leadId !== 'string' || !leadId) {
    throw new HttpsError('invalid-argument', 'leadId is required.', { code: 'BAD_LEAD' });
  }
  if (typeof done !== 'boolean') {
    throw new HttpsError('invalid-argument', 'done must be true or false.', { code: 'BAD_VALUE' });
  }

  const leadRef = db.collection(LEADS).doc(leadId);
  return db.runTransaction(async (tx) => {
    const leadSnap = await tx.get(leadRef);
    if (!leadSnap.exists) throw new HttpsError('not-found', 'That lead no longer exists.', { code: 'NOT_FOUND' });
    const lead = leadSnap.data();
    if (lead.contactedBy !== uid) {
      throw new HttpsError('permission-denied', 'Only the salesman who contacted this lead can mark it a deal.', { code: 'NOT_YOURS' });
    }

    if (done) {
      if (lead.status === DEAL_DONE) return { dealDone: true, changed: false };
      if (lead.status !== 'contacted') {
        throw new HttpsError('failed-precondition', 'Only a contacted lead can be marked a deal done.', { code: 'NOT_CONTACTED' });
      }
      tx.update(leadRef, { status: DEAL_DONE, dealDoneAt: FieldValue.serverTimestamp() });
      return { dealDone: true, changed: true };
    }

    if (lead.status !== DEAL_DONE) return { dealDone: false, changed: false };
    tx.update(leadRef, { status: 'contacted', dealDoneAt: FieldValue.delete() });
    return { dealDone: false, changed: true };
  });
}
