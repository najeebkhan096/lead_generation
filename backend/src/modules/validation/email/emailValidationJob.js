/**
 * Bulk email validation — the email counterpart to `whatsappValidationJob.js`.
 *
 * For each business it (1) crawls the business's website for public contact
 * addresses, then (2) verifies the best candidate is deliverable (syntax,
 * disposable-domain and MX checks). Businesses that come out with a valid
 * address are saved to the `emailLeads` collection as they're found.
 *
 * Same single-running-job / snapshot / cancel shape as the WhatsApp job so
 * the client polls both the same way. Unlike WhatsApp there's no linked
 * account to protect, so a few sites are crawled in parallel instead of one
 * at a time — per-site fetches are still sequential and time-boxed (see
 * `emailDiscoveryService.js`).
 */

import { discoverEmailsFromWebsite } from './emailDiscoveryService.js';
import { createEmailVerificationService } from './emailVerificationService.js';
import { saveEmailLeadsToFirebase } from './emailLeadStore.js';
import { recordEmailCheck } from '../leadChecks.js';

const DEFAULT_CONCURRENCY = 4;
// A site can list several addresses; trying more than a few for one
// business is just DNS lookups for diminishing returns.
const MAX_CANDIDATES_PER_LEAD = 3;
const MAX_LEADS_PER_JOB = 2000;
// Web-search discovery is far slower per business (a paced search plus
// several page fetches), so a single run is kept smaller.
const MAX_WEB_SEARCH_LEADS_PER_JOB = 500;

/** @type {object | null} */
let job = null;

/**
 * Picks the first candidate (already ranked best-first) that verifies as
 * deliverable. Returns the verdict for the best candidate if none do, so the
 * UI can say why ("no_mx", "disposable", …).
 */
async function pickVerified(emails, verifyFn) {
  let firstVerdict = null;
  for (const candidate of emails.slice(0, MAX_CANDIDATES_PER_LEAD)) {
    const verdict = await verifyFn(candidate.email);
    if (!firstVerdict) firstVerdict = { ...verdict, email: candidate.email, source: candidate.source };
    if (verdict.result === 'valid') {
      return { ok: true, email: candidate.email, source: candidate.source, verdict };
    }
  }
  return { ok: false, verdict: firstVerdict };
}

/**
 * @param {object} opts
 * @param {object[]} opts.leads - `{id, website, business, …lead fields}`;
 *   the extra fields are stored on the saved `emailLeads` document.
 * @param {number} [opts.concurrency]
 * @param {boolean} [opts.requireWebsite] - `true` (default) for the
 *   crawl-the-site mode; `false` when `discoverFn` finds emails some other
 *   way (web search for businesses with no website of their own)
 * @param {(website: string, lead: object) => Promise<object>} [opts.discoverFn] - test seam
 * @param {(email: string) => Promise<object>} [opts.verifyFn] - test seam
 * @param {(leads: object[]) => Promise<unknown>} [opts.saveFn] - test seam
 * @param {(lead: object, check: object) => Promise<unknown>} [opts.recordCheckFn]
 *   remembers every outcome (found / none / invalid / unreachable) so a later
 *   run can skip what is already known — see `leadChecks.js`
 * @param {Record<string, object>} [opts.reused] results already known for
 *   leads the caller filtered out of [opts.leads]; seeded into the job's
 *   results so the client sees one complete picture
 */
export function startEmailValidationJob({
  leads,
  concurrency = DEFAULT_CONCURRENCY,
  requireWebsite = true,
  discoverFn = discoverEmailsFromWebsite,
  verifyFn,
  saveFn = saveEmailLeadsToFirebase,
  recordCheckFn = recordEmailCheck,
  reused = {},
}) {
  if (job && job.status === 'running') {
    const err = new Error('An email validation job is already running.');
    err.status = 409;
    throw err;
  }
  const reusedCount = Object.keys(reused).length;
  if (!Array.isArray(leads) || (!leads.length && !reusedCount)) {
    throw new Error('leads array is required');
  }

  const batch = leads
    .map((l) => ({ ...l, id: l?.id || l?.dbId }))
    .filter((l) =>
      requireWebsite ? l?.id && l?.website && String(l.website).trim() : l?.id && l?.business
    );
  if (!batch.length && !reusedCount) {
    throw new Error(
      requireWebsite
        ? 'None of the selected businesses have a website to check.'
        : 'None of the selected businesses can be searched for.'
    );
  }
  const maxLeads = requireWebsite ? MAX_LEADS_PER_JOB : MAX_WEB_SEARCH_LEADS_PER_JOB;
  if (batch.length > maxLeads) {
    const err = new Error(
      `Validate at most ${maxLeads} businesses at a time (you chose ${batch.length}) — pick a category or fewer leads.`
    );
    err.status = 400;
    throw err;
  }

  // Domains repeat across a batch (chains, shared hosts) — verify each
  // address once.
  const verifier = verifyFn ? null : createEmailVerificationService();
  const cache = new Map();
  const verify = async (email) => {
    if (cache.has(email)) return cache.get(email);
    const verdict = await (verifyFn ? verifyFn(email) : verifier.verify(email));
    cache.set(email, verdict);
    return verdict;
  };

  job = {
    status: 'running', // running | done | cancelled
    total: batch.length,
    checked: 0,
    validCount: 0, // a deliverable email was found
    invalidCount: 0, // an email was found but failed verification
    noEmailCount: 0, // site reachable, no public email on it
    errorCount: 0, // site unreachable / unusable
    currentLead: null,
    reusedCount,
    results: { ...reused }, // leadId -> { valid, email, emails, source, result, reason, error }
    startedAt: Date.now(),
    finishedAt: null,
    cancelled: false,
    halted: false, // stopped by the discoverer (search engine blocking us)
    stoppedReason: null,
  };
  const thisJob = job;

  let cursor = 0;

  /** Remembers an outcome. Never lets a bookkeeping failure break the run. */
  async function remember(lead, check) {
    try {
      await recordCheckFn(lead, check);
    } catch (err) {
      console.warn(`Could not record the email check for "${lead.business}":`, err.message || err);
    }
  }

  async function processLead(lead) {
    thisJob.currentLead = { id: lead.id, business: lead.business || null };
    let blocked = false;
    const base = {
      valid: false,
      email: null,
      emails: [],
      source: null,
      foundOn: null,
      website: null,
      result: null,
      reason: null,
      error: null,
    };

    try {
      const found = await discoverFn(lead.website, lead);

      if (!found.emails?.length) {
        // pagesFetched === 0 means we never got a page at all (dead site,
        // bad URL) — a different outcome from "site works, no email on it".
        if (!found.pagesFetched && !found.searched) {
          thisJob.errorCount += 1;
          thisJob.results[lead.id] = { ...base, error: found.lastError || 'Website could not be reached' };
          await remember(lead, { status: 'unreachable', reason: found.lastError || 'Website could not be reached' });
        } else {
          thisJob.noEmailCount += 1;
          thisJob.results[lead.id] = { ...base, reason: 'no_email_found' };
          await remember(lead, { status: 'none', reason: 'no_email_found' });
        }
        return;
      }

      const emails = found.emails.map((e) => e.email);
      const picked = await pickVerified(found.emails, verify);

      if (!picked.ok) {
        thisJob.invalidCount += 1;
        thisJob.results[lead.id] = {
          ...base,
          emails,
          email: picked.verdict?.email || emails[0],
          source: picked.verdict?.source || null,
          foundOn: found.foundOn || null,
          website: found.website || null,
          result: picked.verdict?.result || 'unknown',
          reason: picked.verdict?.reason || null,
        };
        await remember(lead, {
          status: 'invalid',
          address: picked.verdict?.email || emails[0],
          reason: picked.verdict?.reason || picked.verdict?.result || null,
        });
        return;
      }

      thisJob.validCount += 1;
      thisJob.results[lead.id] = {
        ...base,
        valid: true,
        email: picked.email,
        emails,
        source: picked.source,
        foundOn: found.emails.find((e) => e.email === picked.email)?.foundOn || found.foundOn || null,
        website: found.website || null,
        result: 'valid',
        reason: picked.verdict.reason || null,
      };
      await remember(lead, { status: 'found', address: picked.email });

      try {
        const { id, ...fields } = lead;
        await saveFn([
          {
            ...fields,
            id,
            email: picked.email,
            emails: found.emails.map((e) => e.email),
            emailSource: picked.source,
            emailFoundOn: thisJob.results[lead.id].foundOn,
            // A site that turned up during the search is worth keeping, but
            // never overwrites one the lead already had.
            website: fields.website || found.website || null,
            emailStatus: 'valid',
            emailVerified: true,
          },
        ]);
      } catch (saveErr) {
        thisJob.results[lead.id].error = `Verified but failed to save: ${saveErr.message}`;
      }
    } catch (err) {
      if (err.code === 'SEARCH_BLOCKED') {
        blocked = true;
        // Every remaining lookup would be refused the same way — stop the
        // run instead of burning the batch (and getting this IP flagged).
        thisJob.halted = true;
        thisJob.stoppedReason = `${err.message}. Wait a while, then run it again for the rest.`;
        return;
      }
      thisJob.errorCount += 1;
      thisJob.results[lead.id] = { ...base, error: err.message || String(err) };
      await remember(lead, { status: 'unreachable', reason: err.message || String(err) });
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

  return { started: true, total: batch.length, skipped: leads.length - batch.length, reused: reusedCount };
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
    reusedCount: job.reusedCount,
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
