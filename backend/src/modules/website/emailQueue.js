/**
 * A small bounded background queue that looks up the email address of each
 * business that has a website.
 *
 * It runs beside the Google Maps scan, never inside it: the scan hands a
 * business over with `enqueue` and carries on. A fixed number of lookups run
 * at once (`concurrency`), the backlog is capped (`maxPending`), and a failed
 * lookup is logged and dropped — nothing here can throw into the scan.
 *
 * Environment:
 *   EMAIL_EXTRACTION_ENABLED=false   turn the lookups off (website leads still work)
 *   EMAIL_EXTRACTION_CONCURRENCY=3   lookups at once (1–8)
 */

import { crawlSiteForEmails, isRetryableReason } from './websiteFetcher.js';
import { saveEmailResult } from '../leads/emailLeadStore.js';
import { markWebsiteAvailable } from '../leads/websiteLeadStore.js';
import { getChecks, isEmailCheckFresh, recordEmailCheck } from '../validation/leadChecks.js';
import { leadDocId } from '../../lib/leadIdentity.js';

const DEFAULT_CONCURRENCY = 3;
const MAX_CONCURRENCY = 8;
const DEFAULT_MAX_PENDING = 5000;
const TASK_ATTEMPTS = 2; // a transient failure (timeout, network, 5xx) gets one more go
const TASK_RETRY_DELAY_MS = 5000;

const TAG = '[email-extract]';

function hostOf(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return 'invalid-url';
  }
}

/**
 * @param {object} [opts] every dependency is replaceable so tests run offline
 */
export function createEmailQueue({
  concurrency = DEFAULT_CONCURRENCY,
  maxPending = DEFAULT_MAX_PENDING,
  enabled = true,
  crawlFn = crawlSiteForEmails,
  saveEmailFn = saveEmailResult,
  markAvailableFn = markWebsiteAvailable,
  getChecksFn = getChecks,
  recordCheckFn = recordEmailCheck,
  sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
  log = (message, level = 'info') => (level === 'info' ? console.log : console.warn)(`${TAG} ${message}`),
} = {}) {
  const limit = Math.min(MAX_CONCURRENCY, Math.max(1, Math.floor(concurrency) || DEFAULT_CONCURRENCY));
  const pending = [];
  const inFlight = new Set(); // doc ids queued or running, so one business is looked up once
  let active = 0;
  let idleWaiters = [];
  const stats = { queued: 0, found: 0, notFound: 0, checkFailed: 0, notChecked: 0, skippedRecent: 0, dropped: 0, errors: 0 };

  /** Looks up one business. Resolves with the final status; never rejects. */
  async function processSite(site) {
    const host = hostOf(site.website);
    try {
      const checks = await getChecksFn([site]).catch(() => new Map());
      if (isEmailCheckFresh(checks.get(leadDocId(site))?.email)) {
        stats.skippedRecent += 1;
        log(`duplicate skipped: ${host} was checked recently`);
        return 'skipped';
      }

      log(`started: ${host}`);
      let result;
      for (let attempt = 1; attempt <= TASK_ATTEMPTS; attempt++) {
        result = await crawlFn(site.website);
        if (result.status !== 'check_failed' || !isRetryableReason(result.reason)) break;
        if (attempt < TASK_ATTEMPTS) {
          log(`retrying: ${host} (${result.reason})`, 'warn');
          await sleep(TASK_RETRY_DELAY_MS);
        } else {
          log(`permanently failed: ${host} (${result.reason})`, 'warn');
        }
      }

      if (result.status === 'found') {
        stats.found += 1;
        const action = await saveEmailFn(site, result);
        log(`email found: ${host} — ${result.emails.length} address${result.emails.length === 1 ? '' : 'es'} (${action === 'inserted' ? 'lead saved' : 'lead updated'})`);
      } else if (result.status === 'not_found') {
        stats.notFound += 1;
        log(`completed: ${host} — no email published`);
      } else if (result.status === 'check_failed') {
        stats.checkFailed += 1;
        if (!isRetryableReason(result.reason)) log(`request failed: ${host} (${result.reason})`, 'warn');
        // A failure never erases an address stored earlier; this just notes the attempt.
        await saveEmailFn(site, result);
      } else {
        stats.notChecked += 1;
        log(`not checked: ${host} (${result.reason})`);
      }

      // A site that really exists can no longer be listed as having none.
      if (result.status !== 'not_checked' || result.reason !== 'invalid_url') {
        await markAvailableFn(site, result.website || site.website).catch(() => {});
      }
      await recordCheckFn(site, { status: result.status, reason: result.reason, website: result.website || site.website });
      return result.status;
    } catch (err) {
      stats.errors += 1;
      log(`lookup crashed for ${host}: ${err?.message || err}`, 'warn');
      return 'error';
    }
  }

  function notifyIdle() {
    if (active === 0 && pending.length === 0) {
      const waiters = idleWaiters;
      idleWaiters = [];
      waiters.forEach((resolve) => resolve());
    }
  }

  function pump() {
    while (active < limit && pending.length) {
      const site = pending.shift();
      active += 1;
      processSite(site).finally(() => {
        active -= 1;
        inFlight.delete(leadDocId(site));
        pump();
        notifyIdle();
      });
    }
  }

  return {
    /** @returns {'queued'|'duplicate'|'full'|'disabled'} */
    enqueue(site) {
      if (!enabled) return 'disabled';
      const id = leadDocId(site);
      if (inFlight.has(id)) return 'duplicate';
      if (pending.length >= maxPending) {
        stats.dropped += 1;
        return 'full';
      }
      inFlight.add(id);
      pending.push(site);
      stats.queued += 1;
      pump();
      return 'queued';
    },
    /** Resolves when nothing is queued or running. */
    onIdle() {
      return active === 0 && pending.length === 0 ? Promise.resolve() : new Promise((resolve) => idleWaiters.push(resolve));
    },
    snapshot: () => ({ ...stats, pending: pending.length, active, concurrency: limit, enabled }),
  };
}

let shared = null;

/** The one queue the scan uses, configured from the environment. */
export function getEmailQueue() {
  if (!shared) {
    shared = createEmailQueue({
      enabled: String(process.env.EMAIL_EXTRACTION_ENABLED ?? 'true').toLowerCase() !== 'false',
      concurrency: Number(process.env.EMAIL_EXTRACTION_CONCURRENCY) || DEFAULT_CONCURRENCY,
    });
  }
  return shared;
}

export function _resetEmailQueueForTests() {
  shared = null;
}
