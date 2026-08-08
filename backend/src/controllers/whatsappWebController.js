import * as whatsappWeb from '../services/whatsappWebService.js';
import * as whatsappSafety from '../services/whatsappSafety.js';
import {
  startValidationJob,
  getJobSnapshot,
  cancelValidationJob,
} from '../services/whatsappValidationJob.js';
import { listUnvalidatedLeads } from '../services/firebaseLeadStore.js';

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

export async function startAutoValidation(_req, res) {
  try {
    const leads = await listUnvalidatedLeads({ limit: 100 });
    if (!leads.length) {
      return res.json({ success: true, message: 'No leads needing validation found.' });
    }
    const result = startValidationJob({ leads });
    return res.status(202).json({ ...result, message: `Started validation for ${leads.length} leads.` });
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start auto validation' });
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
