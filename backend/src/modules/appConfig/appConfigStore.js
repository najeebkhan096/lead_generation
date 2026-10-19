import crypto from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore, getStorageBucket } from '../../firebase/admin.js';

// The mobile app reads this document (see mobile/lib/services/app_update.dart).
const COLLECTION = 'appConfig';
const DOC_ID = 'android';
const MAX_MESSAGE = 300;
const MIN_APK_BYTES = 1024 * 1024; // a real app is megabytes; this rejects an empty or wrong file

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function docRef() {
  return getFirestore().collection(COLLECTION).doc(DOC_ID);
}

function toConfig(data = {}) {
  return {
    minBuild: Number.isInteger(data.minBuild) ? data.minBuild : 0,
    latestBuild: Number.isInteger(data.latestBuild) ? data.latestBuild : 0,
    apkUrl: typeof data.apkUrl === 'string' ? data.apkUrl : '',
    message: typeof data.message === 'string' ? data.message : '',
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
  };
}

/** Checks a rule from the admin form and returns it in the stored shape. Throws a 400 when it is not valid. */
export function validateRule({ minBuild, latestBuild, message = '' }) {
  if (!Number.isInteger(minBuild) || minBuild < 0) throw httpError(400, 'minBuild must be a whole number, 0 or more');
  if (!Number.isInteger(latestBuild) || latestBuild < 0) throw httpError(400, 'latestBuild must be a whole number, 0 or more');
  if (latestBuild < minBuild) throw httpError(400, 'latestBuild cannot be lower than minBuild');
  if (typeof message !== 'string' || message.length > MAX_MESSAGE) {
    throw httpError(400, `message must be text, ${MAX_MESSAGE} characters or fewer`);
  }
  return { minBuild, latestBuild, message: message.trim() };
}

/** An Android APK is a zip archive, so it starts with "PK". */
export function looksLikeApk(buffer) {
  return Buffer.isBuffer(buffer) && buffer.length >= MIN_APK_BYTES && buffer[0] === 0x50 && buffer[1] === 0x4b;
}

export async function getAppUpdateConfig() {
  const snap = await docRef().get();
  return toConfig(snap.data());
}

/** Saves the minimum and latest builds and the message. The APK link is kept as it is. */
export async function saveAppUpdateRule(input) {
  const rule = validateRule(input);
  await docRef().set({ ...rule, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  return getAppUpdateConfig();
}

/**
 * Stores an APK in Firebase Storage and points the rule at it. The link carries
 * a download token, so it does not expire. The latest build moves up to this
 * build when it is newer.
 */
export async function uploadAppApk({ buffer, buildNumber }) {
  if (!Number.isInteger(buildNumber) || buildNumber < 1) {
    throw httpError(400, 'buildNumber must be the APK\'s build number (a whole number, 1 or more)');
  }
  if (!looksLikeApk(buffer)) throw httpError(400, 'That file is not an Android APK.');

  const bucket = getStorageBucket();
  const storagePath = `app-releases/leadfinder-${buildNumber}.apk`;
  const token = crypto.randomUUID();
  await bucket.file(storagePath).save(buffer, {
    resumable: false,
    metadata: {
      contentType: 'application/vnd.android.package-archive',
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  const apkUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`;

  const current = await getAppUpdateConfig();
  await docRef().set(
    {
      apkUrl,
      latestBuild: Math.max(current.latestBuild, buildNumber),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return getAppUpdateConfig();
}
