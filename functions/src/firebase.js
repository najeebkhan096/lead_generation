import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore as adminFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

function app() {
  return getApps()[0] ?? initializeApp();
}

export const getFirestore = () => adminFirestore(app());
export const getStorageBucket = () => getStorage(app()).bucket();
