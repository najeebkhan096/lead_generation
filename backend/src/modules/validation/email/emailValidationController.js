import { startEmailValidationJob, getEmailJobSnapshot, cancelEmailValidationJob } from './emailValidationJob.js';
import { listUncheckedEmail, summarizeWebsiteLeadValidation } from '../../leads/websiteLeadStore.js';

// A lookup is a paced web search plus a few page fetches (several seconds per
// business), so one run is kept to a size that finishes in a sitting; the
// rest is picked up by running it again.
export const MAX_EMAIL_LEADS_PER_RUN = 500;

/** Email lookup only exists for no-website leads. */
function requireWebsiteLeads(collection) {
  if (collection && collection !== 'websiteLeads') {
    const err = new Error('Email validation is available for websiteLeads only');
    err.status = 400;
    throw err;
  }
}

/**
 * POST /api/email-validation/validate-auto
 *
 * Body: `{ collection?: 'websiteLeads', category?: string, states?: string[], recheck?: boolean }`.
 * Looks up the public email of every no-website lead (in [category] and [states], or all)
 * that has none and has not been looked up yet. `recheck` includes the ones
 * already looked up with nothing found. At most MAX_EMAIL_LEADS_PER_RUN per run.
 */
export async function startAutoValidation(req, res) {
  try {
    const { collection, states: rawStates, recheck, category } = req.body || {};
    requireWebsiteLeads(collection);
    const states = Array.isArray(rawStates) ? rawStates.map((s) => String(s).trim()).filter(Boolean) : undefined;
    const all = await listUncheckedEmail({ states, category, recheck: recheck === true });
    if (!all.length) {
      return res.json({
        success: true,
        message: states?.length ? 'No unchecked businesses in the selected states.' : 'No businesses need an email lookup.',
      });
    }
    const leads = all.slice(0, MAX_EMAIL_LEADS_PER_RUN);
    const result = startEmailValidationJob({ leads });
    const scope = states?.length ? ` in ${states.length} selected state${states.length === 1 ? '' : 's'}` : '';
    const more = all.length > leads.length ? ` ${all.length - leads.length} more are left — run it again for the rest.` : '';
    return res.status(202).json({
      ...result,
      remaining: all.length - leads.length,
      message: `Started the email lookup for ${leads.length} business${leads.length === 1 ? '' : 'es'}${scope}.${more}`,
    });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to start email validation' });
  }
}

/** GET /api/email-validation/unvalidated — per-state progress of the email lookup. */
export async function getUnvalidatedSummary(req, res) {
  try {
    requireWebsiteLeads(req.query?.collection);
    return res.json(await summarizeWebsiteLeadValidation('email', { category: req.query?.category }));
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load email lookup progress' });
  }
}

export function getValidationStatus(_req, res) {
  const snapshot = getEmailJobSnapshot();
  if (!snapshot) return res.json({ active: false, status: 'idle' });
  return res.json({ active: snapshot.status === 'running', ...snapshot });
}

export function cancelValidation(_req, res) {
  return res.json({ success: cancelEmailValidationJob() });
}
