import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { dayKey } from './salesmanStats.js';

const LEADS = 'whatsappLeads';
const LIST_LIMIT = 500;

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/** One contacted lead, in the shape the admin page shows. */
export function toContactedLead(id, data) {
  return {
    id,
    business: data.business || 'Unnamed',
    category: data.category || null,
    location: data.location || null,
    phone: data.phone || null,
    mapsUrl: data.mapsUrl || null,
    rating: typeof data.rating === 'number' ? data.rating : null,
    totalReviews: typeof data.totalReviews === 'number' ? data.totalReviews : null,
    status: data.status || 'contacted',
    contactedAt: data.contactedAt?.toDate?.()?.toISOString() || null,
    reviewText: data.badReview?.text || '',
  };
}

/** Whether moving this lead back to New gives a slot back today. Only a contact made today does. */
export function refundsToday(lead, today) {
  const contactedDay = lead.contactedAt?.toDate ? dayKey(lead.contactedAt.toDate()) : null;
  return contactedDay === today;
}

/** The 1-star WhatsApp leads a salesman has contacted, newest contact first. */
export async function listContactedLeads(uid) {
  const snap = await getFirestore()
    .collection(LEADS)
    .where('sourceType', '==', 'review')
    .where('contactedBy', '==', uid)
    .orderBy('contactedAt', 'desc')
    .limit(LIST_LIMIT)
    .get();
  return snap.docs.map((doc) => toContactedLead(doc.id, doc.data()));
}

/**
 * Moves a contacted lead back to New, as an admin does for a salesman. Today's
 * contact count for that salesman goes down too, when the contact was today.
 */
export async function moveLeadBack(uid, leadId, { now = new Date() } = {}) {
  const db = getFirestore();
  const leadRef = db.collection(LEADS).doc(leadId);
  const today = dayKey(now);
  const counterRef = db.collection('users').doc(uid).collection('contactDays').doc(today);

  return db.runTransaction(async (tx) => {
    // Reads come before writes, as a transaction requires.
    const snap = await tx.get(leadRef);
    if (!snap.exists) throw httpError(404, 'That lead no longer exists.');
    const lead = snap.data();
    if (lead.contactedBy !== uid) throw httpError(409, 'That lead is not contacted by this salesman.');

    const refund = refundsToday(lead, today);
    const used = refund ? ((await tx.get(counterRef)).data()?.count ?? 0) : 0;

    tx.update(leadRef, { status: 'lead', contactedAt: FieldValue.delete(), contactedBy: FieldValue.delete() });
    if (refund) tx.set(counterRef, { count: Math.max(0, used - 1) }, { merge: true });
    return { id: leadId, status: 'lead', refunded: refund };
  });
}
