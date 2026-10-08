import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from '../firebase/admin.js';

/**
 * Verifies the Firebase ID token in `Authorization: Bearer <token>` and that the
 * account is approved (same `users/{uid}.approved` gate the Firestore rules use).
 * Sets req.uid.
 */
export async function requireApprovedUser(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'Missing bearer token', code: 'UNAUTHENTICATED' });

    const db = getFirestore(); // also initialises the Admin app
    const decoded = await getAuth().verifyIdToken(token);
    const user = await db.collection('users').doc(decoded.uid).get();
    if (!user.exists || user.data().approved !== true) {
      return res.status(403).json({ error: 'Account not approved', code: 'FORBIDDEN' });
    }
    req.uid = decoded.uid;
    next();
  } catch (err) {
    if (err.status) return next(err);
    return res.status(401).json({ error: 'Invalid or expired token', code: 'UNAUTHENTICATED' });
  }
}
