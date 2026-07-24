/**
 * Firebase Admin init for Firestore.
 *
 * Credentials (first match wins):
 * 1. FIREBASE_SERVICE_ACCOUNT — full JSON string of the service account
 * 2. FIREBASE_SERVICE_ACCOUNT_PATH — path to JSON file (default: ./firebase-service-account.json)
 * 3. GOOGLE_APPLICATION_CREDENTIALS — standard Google ADC path
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  initializeApp,
  getApps,
  getApp,
  cert,
  applicationDefault,
} from 'firebase-admin/app';
import { getFirestore as getFirestoreAdmin } from 'firebase-admin/firestore';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_SA_PATH = path.resolve(__dirname, '../../firebase-service-account.json');

let initError = null;

function loadServiceAccount() {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT?.trim();
  if (inline) {
    return JSON.parse(inline);
  }

  const saPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim() ||
    process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim() ||
    DEFAULT_SA_PATH;

  if (fs.existsSync(saPath)) {
    return JSON.parse(fs.readFileSync(saPath, 'utf8'));
  }

  return null;
}

export function initFirebase() {
  if (getApps().length) {
    initError = null;
    return getApp();
  }

  try {
    const serviceAccount = loadServiceAccount();
    const projectId =
      process.env.FIREBASE_PROJECT_ID?.trim() ||
      serviceAccount?.project_id ||
      undefined;

    if (!serviceAccount && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      initError =
        'Firebase not configured. Add backend/firebase-service-account.json or set FIREBASE_SERVICE_ACCOUNT.';
      return null;
    }

    const app = serviceAccount
      ? initializeApp({
          credential: cert(serviceAccount),
          projectId,
        })
      : initializeApp({
          credential: applicationDefault(),
          projectId,
        });

    initError = null;
    console.log(`Firebase Admin ready (project: ${projectId || 'default'})`);
    return app;
  } catch (err) {
    initError = err.message || String(err);
    console.error('Firebase init failed:', initError);
    return null;
  }
}

export function getFirestore() {
  const apps = getApps();
  if (!apps.length) {
    const started = initFirebase();
    if (!started) {
      const err = new Error(initError || 'Firebase is not configured');
      err.status = 503;
      throw err;
    }
  }
  return getFirestoreAdmin();
}

export function getFirebaseStatus() {
  const configured = getApps().length > 0;
  return {
    configured,
    error: configured ? null : initError,
  };
}
