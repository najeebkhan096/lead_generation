import * as whatsappWeb from '../services/whatsappWebService.js';
import * as whatsappSafety from '../services/whatsappSafety.js';
import {
  startValidationJob,
  getJobSnapshot,
  cancelValidationJob,
} from '../services/whatsappValidationJob.js';
import { listUnvalidatedLeads, summarizeUnvalidatedLeads } from '../services/firebaseLeadStore.js';

export function getStatus(_req, res) {
  return res.json({ ...whatsappWeb.getStatus(), safety: whatsappSafety.getSafetyStatus() });
}

export function getSafetyStatus(_req, res) {
  return res.json(whatsappSafety.getSafetyStatus());
}

export function connect(_req, res) {
  const result = whatsappWeb.connect();
  return res.status(202).json({ started: true, ...result });
}

export async function disconnect(_req, res) {
  await whatsappWeb.disconnectSession();
  return res.json({ success: true });
}

export function startValidation(req, res) {
  const { leads } = req.body || {};
  if (!Array.isArray(leads) || !leads.length) {
    return res.status(400).json({ error: 'leads array is required' });
  }
  try {
    const result = startValidationJob({ leads });
    return res.status(202).json(result);
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start validation' });
  }
}

/**
 * Validates an explicit `{id, phone, business}[]` list that was never
 * saved to Firestore (e.g. businesses extracted from an Excel archive) —
 * same guarded job engine and rate limiting as [startValidation], but
 * `updateLeadFn` is a no-op instead of the default Firestore `.update()`,
 * since `id` here is a synthetic key, not a real document id.
 */
export function startExternalValidation(req, res) {
  const { leads } = req.body || {};
  if (!Array.isArray(leads) || !leads.length) {
    return res.status(400).json({ error: 'leads array is required' });
  }
  try {
    const result = startValidationJob({ leads, updateLeadFn: async () => {} });
    return res.status(202).json(result);
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start validation' });
  }
}

export async function startAutoValidation(req, res) {
  try {
    const rawStates = req.body?.states;
    const states = Array.isArray(rawStates)
      ? rawStates.map((s) => String(s).trim()).filter(Boolean)
      : undefined;
    const leads = await listUnvalidatedLeads({ states });
    if (!leads.length) {
      return res.json({
        success: true,
        message: states?.length
          ? 'No unvalidated leads found in the selected states.'
          : 'No leads needing validation found.',
      });
    }
    const result = startValidationJob({ leads });
    const scope = states?.length ? ` in ${states.length} selected state${states.length === 1 ? '' : 's'}` : '';
    return res.status(202).json({ ...result, message: `Started validation for ${leads.length} leads${scope}.` });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start auto validation' });
  }
}

export async function getUnvalidatedSummary(_req, res) {
  try {
    const summary = await summarizeUnvalidatedLeads();
    return res.json(summary);
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load unvalidated leads' });
  }
}

export function getValidationStatus(_req, res) {
  const snapshot = getJobSnapshot();
  if (!snapshot) return res.json({ active: false, status: 'idle' });
  return res.json({ active: snapshot.status === 'running', ...snapshot });
}

export function cancelValidation(_req, res) {
  const ok = cancelValidationJob();
  return res.json({ success: ok });
}
