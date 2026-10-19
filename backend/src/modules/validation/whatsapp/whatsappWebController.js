import * as whatsappWeb from './whatsappWebService.js';
import * as whatsappSafety from './whatsappSafety.js';
import { leadSource } from '../../leads/leadSources.js';
import { getChecks, isWhatsAppCheckFresh } from '../leadChecks.js';
import { getVerifiedWhatsAppIds } from './whatsappLeadStore.js';
import { leadDocId } from '../../../lib/leadIdentity.js';
import {
  startValidationJob,
  getJobSnapshot,
  cancelValidationJob,
} from './whatsappValidationJob.js';
import {
  listUnvalidatedLeads,
  summarizeWhatsAppByState,
  getLeadsForValidation,
} from '../../leads/firebaseLeadStore.js';

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

export async function startValidation(req, res) {
  const { leads } = req.body || {};
  if (!Array.isArray(leads) || !leads.length) {
    return res.status(400).json({ error: 'leads array is required' });
  }
  try {
    // The client only sends id/phone/business; read the saved leads back
    // so a verified one lands in `whatsappLeads` with its full details.
    // Anything not found keeps the thin client-supplied shape.
    const full = new Map((await getLeadsForValidation(leads.map((l) => l?.id || l?.dbId))).map((l) => [l.id, l]));
    const merged = leads.map((l) => ({ ...l, ...(full.get(l?.id || l?.dbId) || {}) }));
    const result = startValidationJob({ leads: merged });
    return res.status(202).json(result);
  } catch (err) {
    const status = err.status || 500;
    return res.status(status).json({ error: err.message || 'Failed to start validation' });
  }
}

/**
 * POST /api/whatsapp-web/validate-saved
 *
 * Body: `{ collection: 'leads', ids: string[], recheck?:
 * boolean }` — saved leads of either signal, by Firestore id. Leads with no
 * phone number are skipped, and so are leads already checked (a definite
 * answer — on WhatsApp or not — is stored on the lead); `recheck: true`
 * asks again. The result is written onto the lead and the verified ones are
 * copied into `whatsappLeads`.
 */
export async function startSavedLeadValidation(req, res) {
  const { collection, ids, recheck } = req.body || {};
  if (!Array.isArray(ids) || !ids.length) {
    return res.status(400).json({ error: 'ids array is required' });
  }
  try {
    const source = leadSource(collection);
    const found = await source.load(ids);
    const withPhone = found.filter((l) => l.phone);
    // `whatsAppCheckedAt` is set for a definite answer either way, so a
    // lead that was checked — on WhatsApp or not — isn't asked again.
    const todo = recheck === true ? withPhone : withPhone.filter((l) => !l.whatsAppCheckedAt);
    const alreadyChecked = withPhone.length - todo.length;
    if (!todo.length) {
      return res.status(400).json({
        code: alreadyChecked ? 'ALREADY_CHECKED' : 'NOTHING_TO_CHECK',
        error: !found.length
          ? 'None of the selected businesses were found.'
          : alreadyChecked
            ? `${alreadyChecked} number${alreadyChecked === 1 ? ' was' : 's were'} already checked. Choose "re-check" to ask again.`
            : 'None of the selected businesses have a phone number.',
      });
    }
    const result = startValidationJob({
      leads: todo.map((l) => ({ ...l, id: l.dbId, sourceType: source.sourceType })),
      updateLeadFn: source.setWhatsApp,
    });
    return res.status(202).json({ ...result, alreadyChecked, noPhone: found.length - withPhone.length });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to start validation' });
  }
}

/**
 * Validates an explicit `{id, phone, business, …}[]` list that was never
 * saved to Firestore (e.g. businesses extracted from an Excel archive).
 *
 * Archive leads have no document to carry a "checked" flag, so the
 * `leadChecks` memory stands in for it — keyed by the same id the business
 * has everywhere else:
 *
 *  - answered "on WhatsApp" before (or already a WhatsApp lead) -> reused
 *  - answered "not on WhatsApp" recently                         -> skipped
 *  - never checked / answer too old                              -> checked
 *
 * `recheck: true` asks about every number again. The result of each check
 * is written to the memory; archive leads have no lead document to update,
 * so the per-lead update is a no-op.
 */
export async function startExternalValidation(req, res) {
  const { leads, recheck } = req.body || {};
  if (!Array.isArray(leads) || !leads.length) {
    return res.status(400).json({ error: 'leads array is required' });
  }
  try {
    let toCheck = leads;
    const reused = {};
    let alreadyChecked = 0;

    if (recheck !== true) {
      const withPhone = leads.filter((l) => l?.phone);
      const ids = withPhone.map((l) => leadDocId(l));
      const [checks, verifiedIds] = await Promise.all([getChecks(withPhone), getVerifiedWhatsAppIds(ids)]);
      toCheck = leads.filter((l) => !l?.phone); // job drops these with a clear skip count
      withPhone.forEach((lead, i) => {
        const check = checks.get(ids[i])?.whatsapp;
        if (verifiedIds.has(ids[i]) || (check && check.valid === true && isWhatsAppCheckFresh(check))) {
          reused[lead.id] = { valid: true };
        } else if (check && isWhatsAppCheckFresh(check)) {
          alreadyChecked += 1; // answered "not on WhatsApp"
        } else {
          toCheck.push(lead);
        }
      });
    }

    if (!toCheck.some((l) => l?.phone) && !Object.keys(reused).length) {
      return res.status(400).json({
        code: alreadyChecked ? 'ALREADY_CHECKED' : 'NOTHING_TO_CHECK',
        error: alreadyChecked
          ? `All ${alreadyChecked} number${alreadyChecked === 1 ? ' was' : 's were'} already checked and ${alreadyChecked === 1 ? 'is' : 'are'} not on WhatsApp. Choose "re-check" to ask again.`
          : 'None of the selected leads have a phone number to check.',
      });
    }
    const result = startValidationJob({ leads: toCheck, reused, updateLeadFn: async () => {} });
    return res.status(202).json({ ...result, alreadyChecked });
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
    const summary = await summarizeWhatsAppByState();
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
