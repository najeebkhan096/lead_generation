import {
  saveLeadsToFirebase,
  listFirebaseLeads,
  listFirebaseSearches,
  getFirebaseLeadCount,
  clearAllData,
  updateLeadWhatsAppStatus,
  deleteLead,
  deleteLeadsByCategory,
} from './firebaseLeadStore.js';
import {
  listWebsiteLeads,
  deleteWebsiteLead,
  deleteWebsiteLeadsByCategory,
  getWebsiteLeadCount,
  clearAllWebsiteLeads,
} from './websiteLeadStore.js';
import {
  listEmailLeads,
  deleteEmailLead,
  deleteEmailLeadsByCategory,
  getEmailLeadCount,
  clearAllEmailLeads,
} from '../validation/email/emailLeadStore.js';
import {
  listWhatsAppLeads,
  deleteWhatsAppLead,
  deleteWhatsAppLeadsByCategory,
  getWhatsAppLeadCount,
  clearAllWhatsAppLeads,
} from '../validation/whatsapp/whatsappLeadStore.js';
import { getFirebaseStatus, getFirestore } from '../../firebase/admin.js';
import { listCategories } from '../../lib/pagination.js';
import { getOverview, invalidateOverview } from './overview.js';

const CATEGORY_COLLECTIONS = ['leads', 'websiteLeads', 'whatsappLeads', 'emailLeads'];

/** The paging/filter parameters every lead list accepts — see lib/pagination.js. */
function pageParams(req) {
  const { limit, cursor, category, q } = req.query;
  return {
    limit,
    cursor: cursor ? String(cursor) : undefined,
    category: category ? String(category) : undefined,
    q: q ? String(q).slice(0, 100) : undefined,
  };
}

/**
 * GET /api/db/categories?collection=leads|websiteLeads|whatsappLeads|emailLeads
 * — distinct categories with counts, for the category filter. Cached
 * server-side; `refresh=1` forces a rescan.
 */
export async function getCategories(req, res) {
  try {
    const collection = String(req.query.collection || 'leads');
    if (!CATEGORY_COLLECTIONS.includes(collection)) {
      return res.status(400).json({ error: `collection must be one of: ${CATEGORY_COLLECTIONS.join(', ')}` });
    }
    const categories = await listCategories(getFirestore(), collection, { force: req.query.refresh === '1' });
    return res.json({ collection, categories });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load categories' });
  }
}

/** GET /api/db/overview — the dashboard's numbers, computed server-side. */
export async function getDashboardOverview(req, res) {
  try {
    return res.json(await getOverview({ force: req.query.refresh === '1' }));
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load overview' });
  }
}

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
    const result = await listFirebaseLeads({
      ...pageParams(req),
      verifiedOnly: req.query.verified === '1',
    });
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
    const result = await listWebsiteLeads({
      ...pageParams(req),
      emailOnly: req.query.hasEmail === '1',
    });
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
 * GET /api/db/whatsapp-leads — list leads whose phone number a real
 * WhatsApp check confirmed, from Firestore's `whatsappLeads` collection.
 * Optional `?sourceType=review|website` narrows to one lead signal.
 */
export async function getSavedWhatsAppLeads(req, res) {
  try {
    const sourceType = ['review', 'website'].includes(req.query.sourceType) ? req.query.sourceType : undefined;
    return res.json(await listWhatsAppLeads({ ...pageParams(req), sourceType }));
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load WhatsApp leads' });
  }
}

/** DELETE /api/db/whatsapp-leads/:id — `:id` is the Firestore document id. */
export async function deleteSavedWhatsAppLead(req, res) {
  try {
    await deleteWhatsAppLead(req.params.id);
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to delete WhatsApp lead' });
  }
}

/** DELETE /api/db/whatsapp-leads?category=... — every lead in an exact category. */
export async function deleteSavedWhatsAppLeadsByCategory(req, res) {
  try {
    const category = String(req.query.category || '').trim();
    if (!category) {
      return res.status(400).json({ error: 'category query param is required' });
    }
    const result = await deleteWhatsAppLeadsByCategory(category);
    return res.json({
      success: true,
      ...result,
      message: `Deleted ${result.deleted} WhatsApp lead(s) in category "${category}".`,
    });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to delete WhatsApp leads' });
  }
}

/**
 * GET /api/db/email-leads — list businesses the email validator found and
 * verified a contact email for, from Firestore's `emailLeads` collection.
 */
export async function getSavedEmailLeads(req, res) {
  try {
    const result = await listEmailLeads(pageParams(req));
    return res.json(result);
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to load email leads' });
  }
}

/**
 * DELETE /api/db/email-leads/:id — deletes a single saved email lead.
 * `:id` is the Firestore document id (`dbId` in the API response shape).
 */
export async function deleteSavedEmailLead(req, res) {
  try {
    await deleteEmailLead(req.params.id);
    return res.json({ success: true });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to delete email lead' });
  }
}

/**
 * DELETE /api/db/email-leads?category=... — deletes every saved email lead
 * in an exact category.
 */
export async function deleteSavedEmailLeadsByCategory(req, res) {
  try {
    const category = String(req.query.category || '').trim();
    if (!category) {
      return res.status(400).json({ error: 'category query param is required' });
    }
    const result = await deleteEmailLeadsByCategory(category);
    return res.json({
      success: true,
      ...result,
      message: `Deleted ${result.deleted} email lead(s) in category "${category}".`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to delete email leads' });
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
    const [leadCount, websiteLeadCount, whatsappLeadCount, emailLeadCount] = await Promise.all([
      getFirebaseLeadCount(),
      getWebsiteLeadCount(),
      getWhatsAppLeadCount(),
      getEmailLeadCount(),
    ]);
    return res.json({
      provider: 'firebase',
      configured: true,
      leadCount,
      websiteLeadCount,
      whatsappLeadCount,
      emailLeadCount,
    });
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
    invalidateOverview();
    const [result, websiteLeadsResult, whatsappLeadsResult, emailLeadsResult] = await Promise.all([
      clearAllData(),
      clearAllWebsiteLeads(),
      clearAllWhatsAppLeads(),
      clearAllEmailLeads(),
    ]);
    return res.json({
      success: true,
      ...result,
      deleted: {
        ...result.deleted,
        websiteLeads: websiteLeadsResult.deleted,
        whatsappLeads: whatsappLeadsResult.deleted,
        emailLeads: emailLeadsResult.deleted,
      },
      message:
        `${result.message} Also cleared ${websiteLeadsResult.deleted} website lead(s),` +
        ` ${whatsappLeadsResult.deleted} WhatsApp lead(s) and ${emailLeadsResult.deleted} email lead(s).`,
    });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to clear database' });
  }
}
