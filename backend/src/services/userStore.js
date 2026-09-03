import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';

// Every mobile app account is created here on sign-in with role 'salesman'
// (see mobile/lib/services/auth_service.dart) — this is the only role that
// exists today, but the field is kept explicit rather than assumed.
const COLLECTION = 'users';

function docToUser(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    name: data.name || data.email || 'Unnamed',
    email: data.email || null,
    photoURL: data.photoURL || null,
    role: data.role || 'salesman',
    approved: data.approved === true,
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
