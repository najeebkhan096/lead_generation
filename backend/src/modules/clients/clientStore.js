import { createHash } from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import { clientNameKey, normalizeMapsUrl } from '../../lib/mapsUrl.js';

const COLLECTION = 'clients';

/**
 * A client is a business we sell to: just its name and the link to its
 * Google Maps listing. Orders (the `sales` collection) refer to it by id.
 */
function docToClient(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    businessName: data.businessName || '',
    mapsUrl: data.mapsUrl || null,
    createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
  };
}

/** Deterministic id: the same business name always lands on one document. */
export function clientDocId(name) {
  return createHash('sha1').update(clientNameKey(name)).digest('hex').slice(0, 20);
}

function badRequest(message) {
  const err = new Error(message);
  err.status = 400;
  return err;
}

function cleanName(value) {
  const name = String(value ?? '').trim().replace(/\s+/g, ' ');
  if (!name) throw badRequest('Business name is required');
  return name;
}

function cleanUrl(value) {
  const url = normalizeMapsUrl(value);
  if (!url) throw badRequest('Enter a valid Google Maps link for the business');
  return url;
}

export async function listClients() {
  const snap = await getFirestore().collection(COLLECTION).get();
  const clients = snap.docs.map(docToClient);
  clients.sort((a, b) => a.businessName.localeCompare(b.businessName, undefined, { sensitivity: 'base' }));
  return clients;
}

export async function getClient(id) {
  const doc = await getFirestore().collection(COLLECTION).doc(id).get();
  return doc.exists ? docToClient(doc) : null;
}

/** Both a business name and a Google Maps link are required. */
export async function createClient({ businessName, mapsUrl }) {
  const name = cleanName(businessName);
  const url = cleanUrl(mapsUrl);
  const ref = getFirestore().collection(COLLECTION).doc(clientDocId(name));
  const existing = await ref.get();
  if (existing.exists) {
    const err = new Error(`"${existing.data().businessName}" is already a client`);
    err.status = 409;
    throw err;
  }
  await ref.set({
    businessName: name,
    nameKey: clientNameKey(name),
    mapsUrl: url,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return docToClient(await ref.get());
}

export async function updateClient(id, { businessName, mapsUrl }) {
  const ref = getFirestore().collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) return null;
  const patch = {};
  if (businessName !== undefined) {
    const name = cleanName(businessName);
    const key = clientNameKey(name);
    if (key !== existing.data().nameKey) {
      const clash = await getFirestore().collection(COLLECTION).where('nameKey', '==', key).limit(1).get();
      if (!clash.empty && clash.docs[0].id !== id) {
        const err = new Error(`"${clash.docs[0].data().businessName}" is already a client`);
        err.status = 409;
        throw err;
      }
    }
    patch.businessName = name;
    patch.nameKey = key;
  }
  if (mapsUrl !== undefined) patch.mapsUrl = cleanUrl(mapsUrl);
  await ref.update({ ...patch, updatedAt: FieldValue.serverTimestamp() });
  return docToClient(await ref.get());
}

export async function deleteClient(id) {
  const ref = getFirestore().collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) return false;
  await ref.delete();
  return true;
}
