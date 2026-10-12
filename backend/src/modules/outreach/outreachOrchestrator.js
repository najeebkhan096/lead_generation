/**
 * In-process outreach jobs — same pattern as WhatsApp validation:
 * one running job, pollable snapshot, fire-and-forget IIFE.
 */

import { DEFAULT_BATCH_SIZE, parseLeadRange, SOURCE_COLLECTIONS } from './constants.js';
import { outreachLog } from './logger.js';
import * as store from './outreachStore.js';
import { processLeadPipeline, drainQueue, verifyEmail, discoverEmail } from './outreachPipeline.js';

/** @type {object|null} */
let job = null;
let queueTimer = null;

export function getOutreachJobSnapshot() {
  if (!job) {
    return { status: 'idle', total: 0, processed: 0, failed: 0, current: null };
  }
  return { ...job };
}

export function cancelOutreachJob() {
  if (job && job.status === 'running') {
    job.cancelled = true;
    job.status = 'cancelled';
  }
  return getOutreachJobSnapshot();
}

export async function enrollCampaign(campaignId, { maxLeads = 500 } = {}) {
  const campaign = await store.getCampaign(campaignId);
  const { nextPage } = await store.iterateSourceLeads(campaign.sourceCollection);
  let enrolled = 0;
  let scanned = 0;
  const cap = Math.min(Number(maxLeads) || 500, 2000);

  while (enrolled < cap) {
    const page = await nextPage();
    if (!page.length) break;
    for (const lead of page) {
      scanned += 1;
      if (!store.leadMatchesFilters(lead, campaign.filters)) continue;
      await store.ensureRecord({
        sourceCollection: campaign.sourceCollection,
        sourceLeadId: lead.dbId,
        campaignId,
      });
      enrolled += 1;
      if (enrolled >= cap) break;
    }
  }

  outreachLog('lead_processed', { campaignId, enrolled, scanned });
  return { campaignId, enrolled, scanned };
}

export function startCampaignPipeline({ campaignId, force = false, batchSize = DEFAULT_BATCH_SIZE }) {
  if (job && job.status === 'running') {
    const err = new Error('An outreach job is already running.');
    err.status = 409;
    throw err;
  }

  job = {
    status: 'running',
    kind: 'pipeline',
    campaignId,
    total: 0,
    processed: 0,
    failed: 0,
    current: null,
    startedAt: Date.now(),
    finishedAt: null,
    cancelled: false,
    errors: [],
  };
  const thisJob = job;

  (async () => {
    try {
      await store.updateCampaign(campaignId, { status: 'active' });
      const { enrolled } = await enrollCampaign(campaignId);
      thisJob.total = enrolled;

      let cursor = null;
      while (!thisJob.cancelled) {
        const page = await store.listRecords({
          campaignId,
          limit: Math.min(Number(batchSize) || DEFAULT_BATCH_SIZE, 40),
          cursor,
        });
        if (!page.records.length) break;
        for (const record of page.records) {
          if (thisJob.cancelled) break;
          if (record.outreachApproved) {
            thisJob.processed += 1;
            continue;
          }
          thisJob.current = { id: record.id, business: record.business };
          try {
            await processLeadPipeline(record.id, { force });
            thisJob.processed += 1;
          } catch (err) {
            thisJob.failed += 1;
            thisJob.errors.push({ id: record.id, error: err.message || String(err) });
            await store.setRecordError(record.id, err.message).catch(() => {});
          }
        }
        cursor = page.nextCursor;
        if (!cursor) break;
      }
    } catch (err) {
      thisJob.errors.push({ error: err.message || String(err) });
    } finally {
      if (thisJob.status === 'running') thisJob.status = thisJob.cancelled ? 'cancelled' : 'done';
      thisJob.finishedAt = Date.now();
      thisJob.current = null;
    }
  })();

  return getOutreachJobSnapshot();
}

export function startRangeJob({
  kind = 'validate',
  from = 1,
  to = 20,
  sourceCollection = 'websiteLeads',
  force = false,
} = {}) {
  if (job && job.status === 'running') {
    const err = new Error('An outreach job is already running. Wait for it to finish or cancel it.');
    err.status = 409;
    throw err;
  }
  if (!['validate', 'send'].includes(kind)) {
    const err = new Error('kind must be validate or send');
    err.status = 400;
    throw err;
  }
  if (!SOURCE_COLLECTIONS.includes(sourceCollection)) {
    const err = new Error(`sourceCollection must be one of: ${SOURCE_COLLECTIONS.join(', ')}`);
    err.status = 400;
    throw err;
  }
  const range = parseLeadRange(from, to);

  job = {
    status: 'running',
    kind,
    from: range.from,
    to: range.to,
    sourceCollection,
    total: range.count,
    processed: 0,
    failed: 0,
    skipped: 0,
    emailsFound: 0,
    verified: 0,
    queued: 0,
    current: null,
    startedAt: Date.now(),
    finishedAt: null,
    cancelled: false,
    errors: [],
  };
  const thisJob = job;

  (async () => {
    try {
      const { leads } = await store.listLeadsInRange(sourceCollection, range.from, range.to);
      thisJob.total = leads.length;
      for (const lead of leads) {
        if (thisJob.cancelled) break;
        thisJob.current = { id: lead.dbId, business: lead.business };
        try {
          const record = await store.ensureRecord({
            sourceCollection,
            sourceLeadId: lead.dbId,
          });
          if (kind === 'validate') {
            await discoverEmail(record.id, { force });
            const verified = await verifyEmail(record.id, { force });
            if (verified.email) thisJob.emailsFound += 1;
            if (verified.emailVerified) thisJob.verified += 1;
          } else {
            const updated = await processLeadPipeline(record.id, { force, autoSend: true });
            if (updated.email) thisJob.emailsFound += 1;
            if (updated.emailVerified) thisJob.verified += 1;
            if (updated.outreachStatus === 'queued' || updated.outreachStatus === 'sent') {
              thisJob.queued += 1;
            } else if (!updated.email || updated.emailStatus === 'invalid') {
              thisJob.skipped += 1;
            }
          }
          thisJob.processed += 1;
        } catch (err) {
          thisJob.failed += 1;
          thisJob.processed += 1;
          thisJob.errors.push({ id: lead.dbId, error: err.message || String(err) });
          outreachLog('email_failed', { recordId: `${sourceCollection}_${lead.dbId}`, error: err.message || String(err) });
        }
      }
    } catch (err) {
      thisJob.errors.push({ error: err.message || String(err) });
    } finally {
      if (thisJob.status === 'running') thisJob.status = thisJob.cancelled ? 'cancelled' : 'done';
      thisJob.finishedAt = Date.now();
      thisJob.current = null;
    }
  })();

  return getOutreachJobSnapshot();
}

export function startQueueWorker() {
  if (queueTimer) return;
  let lastIndexWarningAt = 0;
  queueTimer = setInterval(() => {
    drainQueue({ max: 3 }).catch((err) => {
      const msg = err.message || String(err);
      const missingIndex = /FAILED_PRECONDITION|requires an index/i.test(msg);
      if (missingIndex) {
        const now = Date.now();
        if (now - lastIndexWarningAt > 5 * 60 * 1000) {
          lastIndexWarningAt = now;
          outreachLog('lead_processed', {
            worker: true,
            skipped: true,
            reason: 'queue_query_index',
            error: msg.slice(0, 180),
          });
        }
        return;
      }
      outreachLog('email_failed', { worker: true, error: msg });
    });
  }, 20_000);
  if (typeof queueTimer.unref === 'function') queueTimer.unref();
}
