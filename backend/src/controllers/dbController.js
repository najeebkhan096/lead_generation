import {
  saveLeadsToFirebase,
  listFirebaseLeads,
  listFirebaseSearches,
  getFirebaseLeadCount,
  clearAllData,
  updateLeadWhatsAppStatus,
} from '../services/firebaseLeadStore.js';
import { getFirebaseStatus } from '../firebase/admin.js';

const CLEAR_CONFIRM_PHRASE = 'DELETE ALL DATA';

/**
 * POST /api/db/save — persist current session leads to Firebase Firestore.
 */
export async function saveToDatabase(req, res) {
  try {
    const bodyLeads = Array.isArray(req.body?.leads) ? req.body.leads : null;
    const result = await saveLeadsToFirebase(bodyLeads);
    return res.status(201).json({ success: true, ...result });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Save to Firebase failed' });
  }
}

/**
 * GET /api/db/leads — list persisted leads from Firestore.
 */
export async function getSavedLeads(req, res) {
  try {
    const result = await listFirebaseLeads({ limit: req.query.limit });
    return res.json(result);
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to load leads' });
  }
}

/**
 * PATCH /api/db/leads/:id/whatsapp — manually record whether a lead is on
 * WhatsApp, for when this was checked by hand (e.g. on a phone) instead of
 * through the automated WhatsApp Web validation job. `:id` is the
 * Firestore document id (`dbId` in the API response shape).
 */
export async function setLeadWhatsAppStatus(req, res) {
  try {
    if (typeof req.body?.hasWhatsApp !== 'boolean') {
      return res.status(400).json({ error: 'hasWhatsApp (boolean) is required' });
    }
    await updateLeadWhatsAppStatus(req.params.id, { hasWhatsApp: req.body.hasWhatsApp });
    return res.json({ success: true, hasWhatsApp: req.body.hasWhatsApp });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to update WhatsApp status' });
  }
}

/**
 * GET /api/db/searches — list save batches from Firestore.
 */
export async function getSavedSearches(_req, res) {
  try {
    return res.json(await listFirebaseSearches());
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to load searches' });
  }
}

/**
 * GET /api/db/stats
 */
export async function getDbStats(_req, res) {
  try {
    const status = getFirebaseStatus();
    if (!status.configured) {
      return res.status(503).json({
        provider: 'firebase',
        configured: false,
        error: status.error,
        leadCount: 0,
      });
    }
    const leadCount = await getFirebaseLeadCount();
    return res.json({ provider: 'firebase', configured: true, leadCount });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to load stats' });
  }
}

/**
 * POST /api/db/clear — deletes every lead and search record from Firestore.
 * Requires the exact confirm phrase in the body so this can't be triggered
 * by an accidental/misrouted request. Does not touch Firebase Auth users.
 */
export async function clearDatabase(req, res) {
  try {
    if (req.body?.confirm !== CLEAR_CONFIRM_PHRASE) {
      return res.status(400).json({
        error: `Confirmation required. Send { "confirm": "${CLEAR_CONFIRM_PHRASE}" } to proceed.`,
      });
    }
    const result = await clearAllData();
    return res.json({ success: true, ...result });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to clear database' });
  }
}
