/**
 * Bulk email lookup for no-website leads — the email counterpart to
 * `whatsappValidationJob.js`, with the same single-running-job / snapshot /
 * cancel shape so the client polls both the same way.
 *
 * A business with no website has no site to crawl, so for each one the job
 * (1) looks it up on the public web (`webSearchEmailDiscovery.js`), then
 * (2) checks the best address found is deliverable (syntax, disposable-domain
 * and MX). Only an address that passes is stored on the lead.
 *
 * Outcomes written back onto the lead (`updateLeadFn`):
 *   found         a deliverable address — stored
 *   not_found     nothing usable (no address, or none that verified)
 *   check_failed  the lookup itself failed — retried on the next run
 *
 * Searches are serialized and paced inside the discoverer (one IP firing them
 * back to back trips a search engine's bot check), so `concurrency` mostly
 * overlaps page fetching. If the search engine refuses us the whole run stops
 * (`stoppedReason`) instead of burning the batch.
 */

import { discoverEmailsByWebSearch } from './webSearchEmailDiscovery.js';
import { verifyEmailMx } from './emailVerificationService.js';
import { updateWebsiteLeadEmail } from '../../leads/websiteLeadStore.js';

const DEFAULT_CONCURRENCY = 3;
// A page can list several addresses; trying more than a few for one business
// is just DNS lookups for diminishing returns.
const MAX_CANDIDATES_PER_LEAD = 3;

/** @type {object | null} */
let job = null;

async function pickVerified(candidates, verifyFn) {
  let firstVerdict = null;
  for (const candidate of candidates.slice(0, MAX_CANDIDATES_PER_LEAD)) {
    const verdict = await verifyFn(candidate.email);
    if (!firstVerdict) firstVerdict = { ...verdict, email: candidate.email };
    if (verdict.result === 'valid') return { ok: true, candidate, verdict };
  }
  return { ok: false, verdict: firstVerdict };
}

/**
 * @param {object} opts
 * @param {{id: string, business: string, phone?: string, address?: string, location?: string}[]} opts.leads
 *   `id` is the Firestore document id, which keys each result.
 * @param {number} [opts.concurrency]
 * @param {(lead: object) => Promise<object>} [opts.discoverFn] - test seam
 * @param {(email: string) => Promise<object>} [opts.verifyFn] - test seam
 * @param {(id: string, outcome: object) => Promise<unknown>} [opts.updateLeadFn] - test seam
 */
export function startEmailValidationJob({
  leads,
  concurrency = DEFAULT_CONCURRENCY,
  discoverFn = discoverEmailsByWebSearch,
  verifyFn = verifyEmailMx,
  updateLeadFn = updateWebsiteLeadEmail,
}) {
  if (job && job.status === 'running') {
    const err = new Error('An email validation job is already running.');
    err.status = 409;
    throw err;
  }
  const batch = (Array.isArray(leads) ? leads : [])
    .map((l) => ({ ...l, id: l?.id || l?.dbId }))
    .filter((l) => l.id && l.business);
  if (!batch.length) throw new Error('None of the selected businesses can be searched for.');

  // Domains repeat across a batch (chains, shared hosts) — verify each address once.
  const cache = new Map();
  const verify = async (email) => {
    if (!cache.has(email)) cache.set(email, await verifyFn(email));
    return cache.get(email);
  };

  job = {
    status: 'running', // running | done | cancelled
    total: batch.length,
    checked: 0,
    validCount: 0, // a deliverable email was found
    invalidCount: 0, // an address was found but failed verification
    noEmailCount: 0, // the lookup worked, nothing found
    errorCount: 0, // the lookup failed
    currentLead: null,
    results: {}, // leadId -> { valid, email, emails, source, foundOn, result, reason, error }
    startedAt: Date.now(),
    finishedAt: null,
    cancelled: false,
    halted: false,
    stoppedReason: null,
  };
  const thisJob = job;
  let cursor = 0;

  async function save(lead, outcome) {
    try {
      await updateLeadFn(lead.id, outcome);
    } catch (err) {
      thisJob.results[lead.id].error = `Checked but failed to save: ${err.message}`;
    }
  }

  async function processLead(lead) {
    thisJob.currentLead = { id: lead.id, business: lead.business || null };
    const base = { valid: false, email: null, emails: [], source: null, foundOn: null, result: null, reason: null, error: null };
    let blocked = false;
    try {
      const found = await discoverFn(lead);
      const emails = (found.emails || []).map((e) => e.email);

      if (!emails.length) {
        thisJob.noEmailCount += 1;
        thisJob.results[lead.id] = { ...base, reason: 'no_email_found' };
        await save(lead, { status: 'not_found' });
        return;
      }

      const picked = await pickVerified(found.emails, verify);
      if (!picked.ok) {
        thisJob.invalidCount += 1;
        thisJob.results[lead.id] = {
          ...base,
          emails,
          email: picked.verdict?.email || emails[0],
          result: picked.verdict?.result || 'unknown',
          reason: picked.verdict?.reason || null,
        };
        await save(lead, { status: 'not_found' });
        return;
      }

      const { candidate } = picked;
      thisJob.validCount += 1;
      thisJob.results[lead.id] = {
        ...base,
        valid: true,
        email: candidate.email,
        emails,
        source: candidate.source || null,
        foundOn: candidate.foundOn || found.foundOn || null,
        result: 'valid',
        reason: picked.verdict.reason || null,
      };
      await save(lead, {
        status: 'found',
        email: candidate.email,
        emails,
        source: candidate.source || null,
        foundOn: candidate.foundOn || found.foundOn || null,
      });
    } catch (err) {
      if (err.code === 'SEARCH_BLOCKED') {
        blocked = true;
        thisJob.halted = true;
        thisJob.stoppedReason = `${err.message}. Wait a while, then run it again for the rest.`;
        return;
      }
      thisJob.errorCount += 1;
      thisJob.results[lead.id] = { ...base, error: err.message || String(err) };
      await save(lead, { status: 'check_failed' });
    } finally {
      // A lookup the search engine refused was never actually checked.
      if (!blocked) thisJob.checked += 1;
    }
  }

  async function worker() {
    while (!thisJob.cancelled && !thisJob.halted && cursor < batch.length) {
      const lead = batch[cursor];
      cursor += 1;
      await processLead(lead);
    }
  }

  (async () => {
    const workers = Math.max(1, Math.min(concurrency, batch.length));
    await Promise.all(Array.from({ length: workers }, worker));
    thisJob.currentLead = null;
    thisJob.status = thisJob.cancelled ? 'cancelled' : 'done';
    thisJob.finishedAt = Date.now();
  })().catch((err) => {
    thisJob.status = 'cancelled';
    thisJob.stoppedReason = err.message || String(err);
    thisJob.finishedAt = Date.now();
    console.error('Email validation job crashed:', err);
  });

  return { started: true, total: batch.length, skipped: leads.length - batch.length };
}

export function getEmailJobSnapshot() {
  if (!job) return null;
  return {
    status: job.status,
    total: job.total,
    checked: job.checked,
    validCount: job.validCount,
    invalidCount: job.invalidCount,
    noEmailCount: job.noEmailCount,
    errorCount: job.errorCount,
    currentLead: job.currentLead,
    results: job.results,
    startedAt: job.startedAt,
    finishedAt: job.finishedAt,
    elapsedMs: (job.finishedAt || Date.now()) - job.startedAt,
    stoppedReason: job.stoppedReason,
  };
}

export function cancelEmailValidationJob() {
  if (!job || job.status !== 'running') return false;
  job.cancelled = true;
  return true;
}

/** Exposed for tests only. */
export function _resetEmailValidationJobForTests() {
  job = null;
}
