/**
 * Sequential bulk WhatsApp validation — checks a batch of leads' phone
 * numbers one at a time against the live WhatsApp Web session and flags
 * each lead's `hasWhatsApp` field in Firestore.
 *
 * All the actual safety pacing (delays, daily cap, warm-up, circuit
 * breaker) lives in whatsappSafety.js's `guardedCheck`, shared with the
 * inline validation done during scanning (see leadService.js) — this job
 * just walks a queue and calls it, the same as any other caller would.
 */

import * as whatsappWeb from './whatsappWebService.js';
import * as whatsappSafety from './whatsappSafety.js';
import { updateLeadWhatsAppStatus } from './firebaseLeadStore.js';

const MAX_BATCH = 100;

/** @type {Job | null} */
let job = null;

/**
 * @param {object} opts
 * @param {{id: string, phone: string, business?: string}[]} opts.leads
 * @param {(phone: string) => Promise<object>} [opts.checkNumberFn] - test-only seam; defaults to the real safety-guarded checker
 * @param {(id: string, status: object) => Promise<void>} [opts.updateLeadFn] - test-only seam
 */
export function startValidationJob({
  leads,
  checkNumberFn = whatsappSafety.guardedCheck,
  updateLeadFn = updateLeadWhatsAppStatus,
}) {
  if (job && job.status === 'running') {
    const err = new Error('A WhatsApp validation job is already running.');
    err.status = 409;
    throw err;
  }
  if (!Array.isArray(leads) || !leads.length) {
    throw new Error('leads array is required');
  }

  const usingRealChecker = checkNumberFn === whatsappSafety.guardedCheck;
  if (usingRealChecker) {
    if (!whatsappWeb.isReady()) {
      const err = new Error('WhatsApp Web is not connected. Connect it first from the WhatsApp Tool page.');
      err.status = 409;
      throw err;
    }
    const gate = whatsappSafety.canStartBulkJob();
    if (!gate.allowed) {
      const err = new Error(gate.reason);
      err.status = 429;
      throw err;
    }
  }

  const batch = leads.filter((l) => l?.id && l?.phone).slice(0, MAX_BATCH);
  if (!batch.length) {
    throw new Error('None of the selected leads have a phone number to check.');
  }

  job = {
    status: 'running', // running | done | cancelled
    total: batch.length,
    checked: 0,
    validCount: 0,
    invalidCount: 0,
    errorCount: 0,
    currentLead: null,
    results: {}, // leadId -> { valid, error }
    startedAt: Date.now(),
    finishedAt: null,
    cancelled: false,
    stoppedReason: null,
  };
  const thisJob = job;

  (async () => {
    for (const lead of batch) {
      if (thisJob.cancelled) break;
      thisJob.currentLead = { id: lead.id, business: lead.business || null };

      const result = await checkNumberFn(lead.phone);

      if (result.skipped) {
        // Every remaining check would skip for the same reason (cap hit
        // or circuit open) — stop now instead of burning through the rest
        // of the batch doing nothing.
        thisJob.stoppedReason = result.error || 'Stopped for safety';
        break;
      }

      thisJob.checked += 1;

      if (!result.checked) {
        thisJob.errorCount += 1;
        thisJob.results[lead.id] = { valid: false, error: result.error || 'Check failed' };
      } else {
        if (result.valid) thisJob.validCount += 1;
        else thisJob.invalidCount += 1;
        thisJob.results[lead.id] = { valid: result.valid, error: null };
        try {
          await updateLeadFn(lead.id, { hasWhatsApp: result.valid });
        } catch (saveErr) {
          thisJob.results[lead.id].error = `Checked but failed to save: ${saveErr.message}`;
        }
      }
    }

    thisJob.currentLead = null;
    thisJob.status = thisJob.cancelled ? 'cancelled' : 'done';
    thisJob.finishedAt = Date.now();
    if (usingRealChecker) whatsappSafety.recordJobFinished();
  })().catch((err) => {
    thisJob.status = 'cancelled';
    thisJob.finishedAt = Date.now();
    if (usingRealChecker) whatsappSafety.recordJobFinished();
    console.error('WhatsApp validation job crashed:', err);
  });

  return { started: true, total: batch.length, skipped: leads.length - batch.length };
}

export function getJobSnapshot() {
  if (!job) return null;
  return {
    status: job.status,
    total: job.total,
    checked: job.checked,
    validCount: job.validCount,
    invalidCount: job.invalidCount,
    errorCount: job.errorCount,
    currentLead: job.currentLead,
    results: job.results,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
    elapsedMs: (job.finishedAt || Date.now()) - job.startedAt,
    stoppedReason: job.stoppedReason,
  };
}

export function cancelValidationJob() {
  if (!job || job.status !== 'running') return false;
  job.cancelled = true;
  return true;
}

/** Exposed for tests only. */
export function _resetValidationJobForTests() {
  job = null;
}
