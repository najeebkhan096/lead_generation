import { startEmailValidationJob, getEmailJobSnapshot, cancelEmailValidationJob } from './emailValidationJob.js';
import { listUncheckedEmail, summarizeWebsiteLeadValidation } from '../../leads/websiteLeadStore.js';
import { trackRun } from '../validationRuns.js';

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
 * Starts the email lookup over the no-website leads that have none and have not
 * been looked up yet (in [category] and [states], when given), at most
 * MAX_EMAIL_LEADS_PER_RUN, and records the run so it can be resumed. A lead
 * already looked up is skipped, so starting the same scope again continues
 * where an interrupted run stopped. `recheck` includes the ones already looked
 * up with nothing found.
 */
export async function launchEmailValidation({ states, category, recheck = false }, { startJob = startEmailValidationJob, track = trackRun } = {}) {
  const all = await listUncheckedEmail({ states, category, recheck });
  if (!all.length) {
    return {
      started: false,
      message: states?.length ? 'No unchecked businesses in the selected states.' : 'No businesses need an email lookup.',
    };
  }
  const leads = all.slice(0, MAX_EMAIL_LEADS_PER_RUN);
  const result = startJob({ leads });
  const runId = track({
    kind: 'email',
    collection: 'websiteLeads',
    category: category || null,
    states: states || [],
    recheck,
    getSnapshot: getEmailJobSnapshot,
  });
  const scope = states?.length ? ` in ${states.length} selected state${states.length === 1 ? '' : 's'}` : '';
  const more = all.length > leads.length ? ` ${all.length - leads.length} more are left — run it again for the rest.` : '';
  return {
    started: true,
    result,
    runId,
    remaining: all.length - leads.length,
    message: `Started the email lookup for ${leads.length} business${leads.length === 1 ? '' : 'es'}${scope}.${more}`,
  };
}

/**
 * POST /api/email-validation/validate-auto
 *
 * Body: `{ collection?: 'websiteLeads', category?: string, states?: string[], recheck?: boolean }`.
 */
export async function startAutoValidation(req, res) {
  try {
    const { collection, states: rawStates, recheck, category } = req.body || {};
    requireWebsiteLeads(collection);
    const states = Array.isArray(rawStates) ? rawStates.map((s) => String(s).trim()).filter(Boolean) : undefined;
    const out = await launchEmailValidation({ states, category, recheck: recheck === true });
    if (!out.started) return res.json({ success: true, message: out.message });
    return res.status(202).json({ ...out.result, runId: out.runId, remaining: out.remaining, message: out.message });
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
