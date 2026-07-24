import {
  saveLeadsToFirebase,
  listFirebaseLeads,
  listFirebaseSearches,
  getFirebaseLeadCount,
} from '../services/firebaseLeadStore.js';
import { getFirebaseStatus } from '../firebase/admin.js';

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
