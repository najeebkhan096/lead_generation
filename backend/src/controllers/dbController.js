import {
  saveLeadsToFirebase,
  listFirebaseLeads,
  listFirebaseSearches,
  getFirebaseLeadCount,
  clearAllData,
  updateLeadWhatsAppStatus,
  deleteLead,
  deleteLeadsByCategory,
} from '../services/firebaseLeadStore.js';
import {
  listWebsiteLeads,
  deleteWebsiteLead,
  deleteWebsiteLeadsByCategory,
  getWebsiteLeadCount,
  clearAllWebsiteLeads,
} from '../services/websiteLeadStore.js';
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
 * DELETE /api/db/leads/:id — deletes a single saved lead. `:id` is the
 * Firestore document id (`dbId` in the API response shape).
 */
export async function deleteSavedLead(req, res) {
  try {
    await deleteLead(req.params.id);
    return res.json({ success: true });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to delete lead' });
  }
}

/**
 * DELETE /api/db/leads?category=... — deletes every saved lead in an
 * exact category (the country-tagged string, e.g. "cleaning services UK").
 */
export async function deleteSavedLeadsByCategory(req, res) {
  try {
    const category = String(req.query.category || '').trim();
    if (!category) {
      return res.status(400).json({ error: 'category query param is required' });
    }
    const result = await deleteLeadsByCategory(category);
    return res.json({
      success: true,
      ...result,
      message: `Deleted ${result.deleted} lead(s) in category "${category}".`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to delete leads' });
  }
}

/**
 * GET /api/db/website-leads — list businesses discovered during scans that
 * have no website, from Firestore's `websiteLeads` collection.
 */
export async function getSavedWebsiteLeads(req, res) {
  try {
    const result = await listWebsiteLeads({ limit: req.query.limit });
    return res.json(result);
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to load website leads' });
  }
}

/**
 * DELETE /api/db/website-leads/:id — deletes a single saved website lead.
 * `:id` is the Firestore document id (`dbId` in the API response shape).
 */
export async function deleteSavedWebsiteLead(req, res) {
  try {
    await deleteWebsiteLead(req.params.id);
    return res.json({ success: true });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to delete website lead' });
  }
}

/**
 * DELETE /api/db/website-leads?category=... — deletes every saved website
 * lead in an exact category.
 */
export async function deleteSavedWebsiteLeadsByCategory(req, res) {
  try {
    const category = String(req.query.category || '').trim();
    if (!category) {
      return res.status(400).json({ error: 'category query param is required' });
    }
    const result = await deleteWebsiteLeadsByCategory(category);
    return res.json({
      success: true,
      ...result,
      message: `Deleted ${result.deleted} website lead(s) in category "${category}".`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to delete website leads' });
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
    const [leadCount, websiteLeadCount] = await Promise.all([
      getFirebaseLeadCount(),
      getWebsiteLeadCount(),
    ]);
    return res.json({ provider: 'firebase', configured: true, leadCount, websiteLeadCount });
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
    const [result, websiteLeadsResult] = await Promise.all([
      clearAllData(),
      clearAllWebsiteLeads(),
    ]);
    return res.json({
      success: true,
      ...result,
      deleted: { ...result.deleted, websiteLeads: websiteLeadsResult.deleted },
      message: `${result.message} Also cleared ${websiteLeadsResult.deleted} website lead(s).`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to clear database' });
  }
}
