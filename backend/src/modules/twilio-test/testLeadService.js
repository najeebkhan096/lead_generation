/**
 * Test leads for the Twilio outreach flow, managed from the web admin.
 *
 * Writes the same `outreachLeads` / `outreachConversations` docs the mobile
 * Outreach tab reads (see functions/src/twilioChat/messageService.js), tagged
 * `isTest: true` so they can be listed and removed without touching real
 * leads. Needs no Twilio credentials: nothing is sent from here.
 */
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { HttpError, isValidE164, leadIdFor, normalizePhone } from '../twilio-chat/validation.js';

const LEADS = 'outreachLeads';
const CONVS = 'outreachConversations';
const LIST_LIMIT = 50;

/** Owner for leads created without an explicit one (must match no real uid). */
export const defaultOwnerId = () => process.env.TWILIO_TEST_OWNER_ID || 'web-admin';

const OWNER_RE = /^[A-Za-z0-9_-]{1,128}$/;
const clip = (v, max) => String(v ?? '').trim().slice(0, max);

const millis = (ts) => (typeof ts?.toMillis === 'function' ? ts.toMillis() : null);

function toJson(id, d) {
  return {
    id,
    name: d.name ?? '',
    businessName: d.businessName ?? '',
    phoneNumber: d.phoneNumber ?? '',
    ownerId: d.ownerId ?? '',
    createdAt: millis(d.createdAt),
  };
}

/**
 * Creates the test lead + conversation. Idempotent per owner and number: an
 * existing lead is returned untouched, with `isTest` telling whether it was
 * created here (a real lead is never converted into a test lead).
 */
export async function createTestLead({ name, businessName, phoneNumber, ownerId }, { db = getFirestore() } = {}) {
  const phone = normalizePhone(phoneNumber);
  if (!isValidE164(phone)) throw new HttpError(400, 'Phone must be E.164 (+countrycode…).', 'INVALID_PHONE');
  const owner = clip(ownerId, 128) || defaultOwnerId();
  if (!OWNER_RE.test(owner)) throw new HttpError(400, 'Owner id may only contain letters, digits, - and _.', 'INVALID_OWNER');

  const id = leadIdFor(owner, phone);
  const leadRef = db.collection(LEADS).doc(id);
  const convRef = db.collection(CONVS).doc(id);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(leadRef);
    if (snap.exists) {
      const cur = snap.data();
      return { lead: toJson(id, cur), created: false, isTest: cur.isTest === true };
    }
    const now = FieldValue.serverTimestamp();
    const data = {
      id, ownerId: owner, name: clip(name, 120) || phone, businessName: clip(businessName, 160), phoneNumber: phone,
      profileImage: null, details: {}, isTest: true, source: 'web-test',
      createdAt: now, updatedAt: now, lastMessage: '', lastMessageType: null, lastMessageAt: null, unreadCount: 0,
    };
    tx.set(leadRef, data);
    tx.set(convRef, { id, ownerId: owner, leadId: id, phoneNumber: phone, lastInboundAt: null, lastOutboundAt: null, createdAt: now }, { merge: true });
    // The server timestamp is not readable until commit; report "now".
    return { lead: toJson(id, { ...data, createdAt: { toMillis: () => Date.now() } }), created: true, isTest: true };
  });
}

/** Newest test leads first. Equality filter only, so no composite index is needed. */
export async function listTestLeads({ db = getFirestore() } = {}) {
  const snap = await db.collection(LEADS).where('isTest', '==', true).get();
  return snap.docs
    .map((doc) => toJson(doc.id, doc.data()))
    .sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))
    .slice(0, LIST_LIMIT);
}

/** Deletes a test lead and its conversation (with any messages). Refuses real leads. */
export async function deleteTestLead(leadId, { db = getFirestore() } = {}) {
  const id = String(leadId ?? '');
  const leadRef = db.collection(LEADS).doc(id);
  const snap = id ? await leadRef.get() : null;
  if (!snap?.exists) throw new HttpError(404, 'Lead not found.', 'LEAD_NOT_FOUND');
  if (snap.data().isTest !== true) throw new HttpError(403, 'Only test leads can be deleted here.', 'NOT_A_TEST_LEAD');
  await db.recursiveDelete(db.collection(CONVS).doc(id));
  await leadRef.delete();
}
