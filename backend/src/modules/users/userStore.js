import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';

// Every mobile app account is created here on sign-in with role 'salesman'
// (see mobile/lib/services/auth_service.dart) — this is the only role that
// exists today, but the field is kept explicit rather than assumed.
const COLLECTION = 'users';

// New WhatsApp leads a salesman may contact per day when no admin has set a
// limit. Must match DEFAULT_DAILY_LEAD_LIMIT in functions/src/leadContact.js,
// which enforces it.
export const DEFAULT_DAILY_LEAD_LIMIT = 10;
const MAX_DAILY_LEAD_LIMIT = 1000;

function docToUser(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    name: data.name || data.email || 'Unnamed',
    email: data.email || null,
    photoURL: data.photoURL || null,
    role: data.role || 'salesman',
    approved: data.approved === true,
    dailyLeadLimit: Number.isInteger(data.dailyLeadLimit) ? data.dailyLeadLimit : DEFAULT_DAILY_LEAD_LIMIT,
    createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    lastLoginAt: data.lastLoginAt?.toDate?.()?.toISOString() || null,
  };
}

export async function listUsers({ role } = {}) {
  const db = getFirestore();
  let query = db.collection(COLLECTION);
  if (role) query = query.where('role', '==', role);
  const snap = await query.get();
  const users = snap.docs.map(docToUser);
  users.sort((a, b) => {
    if (a.approved !== b.approved) return a.approved ? 1 : -1;
    return a.name.localeCompare(b.name);
  });
  return users;
}

export async function setUserApproved(id, approved) {
  if (typeof approved !== 'boolean') {
    const err = new Error('approved must be true or false');
    err.status = 400;
    throw err;
  }
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) {
    const err = new Error('User not found');
    err.status = 404;
    throw err;
  }
  await ref.update({
    approved,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return docToUser(await ref.get());
}

/** `limit` is a whole number of new leads per day, or null for the default. */
export async function setUserDailyLeadLimit(id, limit) {
  const reset = limit === null;
  if (!reset && !(Number.isInteger(limit) && limit >= 0 && limit <= MAX_DAILY_LEAD_LIMIT)) {
    const err = new Error(`dailyLeadLimit must be a whole number from 0 to ${MAX_DAILY_LEAD_LIMIT}, or null for the default`);
    err.status = 400;
    throw err;
  }
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) {
    const err = new Error('User not found');
    err.status = 404;
    throw err;
  }
  console.log('[DEBUG dailyLeadLimit] %s before=%j requested=%j', id, existing.data().dailyLeadLimit, limit);
  await ref.update({
    dailyLeadLimit: reset ? FieldValue.delete() : limit,
    updatedAt: FieldValue.serverTimestamp(),
  });
  const saved = await ref.get();
  const returned = docToUser(saved);
  console.log('[DEBUG dailyLeadLimit] %s after=%j returned=%j', id, saved.data().dailyLeadLimit, returned.dailyLeadLimit);
  return returned;
}

export async function setUserRole(id, role) {
  if (!['admin', 'salesman'].includes(role)) {
    const err = new Error('role must be admin or salesman');
    err.status = 400;
    throw err;
  }
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) {
    const err = new Error('User not found');
    err.status = 404;
    throw err;
  }
  await ref.update({
    role,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return docToUser(await ref.get());
}
