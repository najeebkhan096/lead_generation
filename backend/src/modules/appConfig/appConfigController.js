import { getAppUpdateConfig, saveAppUpdateRule, uploadAppApk } from './appConfigStore.js';

function sendError(res, err) {
  return res.status(err.status || 500).json({ error: err.message || 'Request failed' });
}

export async function getAppUpdate(_req, res) {
  try {
    return res.json(await getAppUpdateConfig());
  } catch (err) {
    return sendError(res, err);
  }
}

export async function saveAppUpdate(req, res) {
  try {
    const { minBuild, latestBuild, message } = req.body || {};
    return res.json(await saveAppUpdateRule({ minBuild, latestBuild, message }));
  } catch (err) {
    return sendError(res, err);
  }
}

/** POST /api/app-config/android/apk?buildNumber=2 — the APK file as the request body. */
export async function uploadApk(req, res) {
  try {
    if (!Buffer.isBuffer(req.body) || !req.body.length) {
      return res.status(400).json({ error: 'Send the APK file as the request body.' });
    }
    return res.json(await uploadAppApk({ buffer: req.body, buildNumber: Number(req.query.buildNumber) }));
  } catch (err) {
    return sendError(res, err);
  }
}
