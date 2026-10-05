/**
 * Per-lead pipeline steps. Each step is independently callable and
 * caches completed work unless `force` is set.
 */

import crypto from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { discoverEmailsFromWebsite, normalizeEmail } from './emailDiscoveryService.js';
import { createEmailVerificationService } from './emailVerificationService.js';
import { analyzeWebsite } from './websiteAnalysisService.js';
import { generateOutreachEmail } from './aiEmailGeneratorService.js';
import { createEmailSenderService, isTemporarySendFailure } from './emailSenderService.js';
import { outreachLog } from './logger.js';
import { TERMINAL_NO_FOLLOW_UP } from './constants.js';
import * as store from './outreachStore.js';

function appendUnsubscribeFooter(body, settings, token) {
  const base = (settings.publicBaseUrl || '').replace(/\/$/, '');
  if (!base || !token) return body;
  const url = `${base}/api/outreach/unsubscribe?t=${encodeURIComponent(token)}`;
  return `${body.trim()}\n\n---\nIf you would rather not hear from us, you can unsubscribe here:\n${url}`;
}

export async function discoverEmail(recordId, { force = false } = {}) {
  let record = await store.getRecord(recordId);
  if (record.email && record.emailSource && !force) {
    outreachLog('email_discovered', { recordId, cached: true });
    return record;
  }
  const result = await discoverEmailsFromWebsite(record.website);
  const patch = {
    emails: result.emails,
    lastEvent: 'email_discovered',
  };
  if (result.primary) {
    patch.email = result.primary;
    patch.emailSource = result.emailSource;
    patch.outreachStatus = record.outreachApproved ? record.outreachStatus : 'email_found';
    patch.lastError = null;
  } else if (record.email) {
    patch.emailSource = patch.emailSource || record.emailSource || 'manual';
  } else {
    patch.lastError = result.lastError || 'No public email found';
    patch.lastErrorAt = FieldValue.serverTimestamp();
  }
  record = await store.updateRecord(recordId, patch);
  await store.logEvent({
    type: 'email_discovered',
    recordId,
    campaignId: record.campaignId,
    message: result.primary ? result.primary.split('@')[1] : result.lastError,
  });
  outreachLog('email_discovered', { recordId, found: Boolean(result.primary), pagesFetched: result.pagesFetched });
  return record;
}

export async function verifyEmail(recordId, { force = false } = {}) {
  let record = await store.getRecord(recordId);
  if (!record.email) {
    record = await discoverEmail(recordId);
  }
  if (!record.email) {
    return store.updateRecord(recordId, {
      emailStatus: 'invalid',
      emailVerified: false,
      outreachStatus: 'email_invalid',
      lastError: record.lastError || 'No email to verify',
      lastErrorAt: FieldValue.serverTimestamp(),
    });
  }
  if (record.emailVerified && !force) return record;

  if (await store.isUnsubscribed(record.email)) {
    const updated = await store.updateRecord(recordId, {
      unsubscribeStatus: true,
      outreachStatus: 'unsubscribed',
      lastEvent: 'unsubscribed',
    });
    await store.logEvent({ type: 'unsubscribed', recordId, campaignId: record.campaignId, message: 'blocked at verify' });
    return updated;
  }

  const verifier = createEmailVerificationService();
  const result = await verifier.verify(record.email);
  const verified = result.result === 'valid';
  const status = verified ? 'email_verified' : result.result === 'invalid' ? 'email_invalid' : record.outreachStatus;
  const updated = await store.updateRecord(recordId, {
    emailStatus: result.result,
    emailVerified: verified,
    outreachStatus: ['approved', 'queued', 'sent', 'delivered', 'opened', 'replied', 'interested'].includes(record.outreachStatus)
      ? record.outreachStatus
      : status,
    lastError: verified ? null : result.reason,
    lastErrorAt: verified ? null : FieldValue.serverTimestamp(),
    lastEvent: 'email_verified',
  });
  await store.logEvent({
    type: 'email_verified',
    recordId,
    campaignId: record.campaignId,
    message: `${result.result}:${result.provider}`,
  });
  outreachLog('email_verified', { recordId, result: result.result, provider: result.provider });
  return updated;
}

export async function analyzeRecordWebsite(recordId, { force = false } = {}) {
  let record = await store.getRecord(recordId);
  if (record.websiteAnalysisStatus === 'completed' && record.websiteAnalysis && !force) {
    return record;
  }
  await store.updateRecord(recordId, { websiteAnalysisStatus: 'running' });
  try {
    const analysis = await analyzeWebsite(record.website);
    const updated = await store.updateRecord(recordId, {
      websiteAnalysis: analysis,
      websiteAnalysisStatus: 'completed',
      lastError: analysis.lastError || null,
      lastEvent: 'website_analyzed',
    });
    await store.logEvent({
      type: 'website_analyzed',
      recordId,
      campaignId: record.campaignId,
      message: `score=${analysis.score}`,
    });
    outreachLog('website_analyzed', { recordId, score: analysis.score, skipped: analysis.skipped || false });
    return updated;
  } catch (err) {
    await store.updateRecord(recordId, { websiteAnalysisStatus: 'failed' });
    await store.setRecordError(recordId, err.message);
    throw err;
  }
}

export async function generateEmail(recordId, { force = false } = {}) {
  let record = await store.getRecord(recordId);
  if (record.emailGenerationStatus === 'completed' && record.generatedBody && !force) {
    return record;
  }
  if (record.websiteAnalysisStatus !== 'completed' || !record.websiteAnalysis) {
    record = await analyzeRecordWebsite(recordId);
  }
  const settings = await store.getSettings();
  await store.updateRecord(recordId, { emailGenerationStatus: 'running' });
  try {
    const generated = await generateOutreachEmail({
      business: record.business,
      category: record.category,
      location: record.location,
      website: record.website,
      analysis: record.websiteAnalysis,
      senderName: settings.senderName,
    });
    const updated = await store.updateRecord(recordId, {
      generatedSubject: generated.subject,
      generatedBody: generated.body,
      generatedAt: FieldValue.serverTimestamp(),
      aiModel: generated.model,
      emailGenerationStatus: 'completed',
      outreachApproved: false,
      outreachStatus: record.outreachStatus === 'not_processed' || record.outreachStatus === 'email_found' || record.outreachStatus === 'email_verified'
        ? 'ready_for_review'
        : record.outreachStatus,
      lastError: generated.lastError || null,
      lastEvent: 'ai_email_generated',
    });
    await store.logEvent({ type: 'ai_email_generated', recordId, campaignId: record.campaignId, message: generated.model });
    outreachLog('ai_email_generated', { recordId, model: generated.model });
    return updated;
  } catch (err) {
    await store.updateRecord(recordId, { emailGenerationStatus: 'failed' });
    await store.setRecordError(recordId, err.message);
    throw err;
  }
}

const ALREADY_SENT = ['queued', 'sent', 'delivered', 'opened', 'replied', 'interested', 'unsubscribed', 'not_interested', 'paused', 'bounced'];

export async function processLeadPipeline(recordId, { force = false, autoSend = false } = {}) {
  outreachLog('lead_processed', { recordId, stage: 'start', autoSend });
  await discoverEmail(recordId, { force });
  await verifyEmail(recordId, { force });
  if (!autoSend) {
    await analyzeRecordWebsite(recordId, { force });
    const record = await generateEmail(recordId, { force });
    await store.logEvent({ type: 'lead_processed', recordId, campaignId: record.campaignId });
    return record;
  }

  let record = await store.getRecord(recordId);
  if (ALREADY_SENT.includes(record.outreachStatus)) return record;
  if (!record.email || record.emailStatus === 'invalid' || record.unsubscribeStatus) return record;

  await analyzeRecordWebsite(recordId, { force });
  record = await generateEmail(recordId, { force });
  if (!record.generatedSubject || !record.generatedBody) return record;
  await approveAndQueue(recordId);
  await store.logEvent({ type: 'lead_processed', recordId, campaignId: record.campaignId });
  return store.getRecord(recordId);
}

export async function approveAndQueue(recordId, { subject, body } = {}) {
  let record = await store.getRecord(recordId);
  if (record.unsubscribeStatus) {
    const err = new Error('This address has unsubscribed — it will not be queued.');
    err.status = 409;
    throw err;
  }
  if (await store.isUnsubscribed(record.email)) {
    await store.updateRecord(recordId, { unsubscribeStatus: true, outreachStatus: 'unsubscribed' });
    const err = new Error('This address is on the unsubscribe list.');
    err.status = 409;
    throw err;
  }
  if (!record.email) {
    const err = new Error('Cannot approve without an email address.');
    err.status = 400;
    throw err;
  }
  if (record.emailStatus === 'invalid') {
    const err = new Error('Cannot approve an invalid email.');
    err.status = 400;
    throw err;
  }

  const settings = await store.getSettings();
  const token = crypto.randomBytes(24).toString('hex');
  const finalSubject = (subject ?? record.generatedSubject ?? '').trim();
  let finalBody = (body ?? record.generatedBody ?? '').trim();
  if (!finalSubject || !finalBody) {
    const err = new Error('Subject and body are required before approval.');
    err.status = 400;
    throw err;
  }
  finalBody = appendUnsubscribeFooter(finalBody, settings, token);

  const campaign = record.campaignId ? await store.getCampaign(record.campaignId).catch(() => null) : null;
  const testMode = settings.testMode || campaign?.testMode === true;
  const intended = record.email;
  const recipient = testMode ? (settings.testEmail || intended) : intended;
  if (testMode && !settings.testEmail) {
    const err = new Error('Test mode is on but no test email is configured.');
    err.status = 400;
    throw err;
  }

  record = await store.updateRecord(recordId, {
    generatedSubject: finalSubject,
    generatedBody: finalBody,
    outreachApproved: true,
    outreachStatus: 'queued',
    unsubscribeToken: token,
    lastEvent: 'email_approved',
  });

  const item = await store.enqueueEmail({
    leadId: record.sourceLeadId,
    recordId: record.id,
    campaignId: record.campaignId,
    recipient,
    intendedRecipient: intended,
    subject: finalSubject,
    body: finalBody,
    kind: 'initial',
    scheduledAt: new Date(),
    testMode,
  });

  await store.logEvent({ type: 'email_approved', recordId, campaignId: record.campaignId, queueId: item.id });
  await store.logEvent({ type: 'email_queued', recordId, campaignId: record.campaignId, queueId: item.id });
  outreachLog('email_approved', { recordId, testMode });
  outreachLog('email_queued', { recordId, queueId: item.id, testMode });
  return { record, queue: item };
}

export async function rejectRecord(recordId) {
  const record = await store.updateRecord(recordId, {
    outreachApproved: false,
    outreachStatus: 'not_interested',
    lastEvent: 'email_rejected',
  });
  await store.logEvent({ type: 'email_rejected', recordId, campaignId: record.campaignId });
  return record;
}

export async function markStatus(recordId, outreachStatus) {
  const record = await store.updateRecord(recordId, { outreachStatus, lastEvent: 'status_changed' });
  await store.logEvent({ type: 'status_changed', recordId, campaignId: record.campaignId, message: outreachStatus });
  if (outreachStatus === 'unsubscribed' && record.email) {
    await store.addUnsubscribe(record.email, { recordId, reason: 'manual' });
    await store.updateRecord(recordId, { unsubscribeStatus: true });
  }
  if (outreachStatus === 'not_interested' || outreachStatus === 'paused') {
    await cancelPendingForRecord(recordId, 'status_changed');
  }
  return store.getRecord(recordId);
}

async function cancelPendingForRecord(recordId, reason) {
  const items = await store.listQueue({ limit: 200 });
  for (const item of items) {
    if (item.recordId === recordId && item.status === 'pending') {
      await store.updateQueueItem(item.id, { status: 'cancelled', error: reason });
      await store.logEvent({ type: 'follow_up_cancelled', recordId, queueId: item.id, message: reason });
      outreachLog('follow_up_cancelled', { recordId, queueId: item.id, reason });
    }
  }
}

export async function sendQueueItem(item, { sender, settings } = {}) {
  const record = await store.getRecord(item.recordId);
  if (record.unsubscribeStatus || await store.isUnsubscribed(record.email) || await store.isUnsubscribed(item.intendedRecipient)) {
    await store.updateQueueItem(item.id, { status: 'cancelled', error: 'unsubscribed' });
    await store.updateRecord(item.recordId, { unsubscribeStatus: true, outreachStatus: 'unsubscribed' });
    outreachLog('email_failed', { recordId: item.recordId, reason: 'unsubscribed' });
    return { skipped: true, reason: 'unsubscribed' };
  }
  if (TERMINAL_NO_FOLLOW_UP.includes(record.outreachStatus) && item.kind !== 'initial') {
    await store.updateQueueItem(item.id, { status: 'cancelled', error: `blocked_status:${record.outreachStatus}` });
    await store.logEvent({ type: 'follow_up_cancelled', recordId: item.recordId, queueId: item.id, message: record.outreachStatus });
    return { skipped: true, reason: record.outreachStatus };
  }
  let dailyLimit = settings.defaultDailyLimit;
  if (record.campaignId) {
    const campaign = await store.getCampaign(record.campaignId).catch(() => null);
    if (campaign && campaign.status !== 'active' && item.kind !== 'initial') {
      await store.updateQueueItem(item.id, { status: 'cancelled', error: `campaign_${campaign.status}` });
      return { skipped: true, reason: 'campaign_not_active' };
    }
    if (campaign?.dailyLimit) dailyLimit = campaign.dailyLimit;
  }
  const sentToday = await store.countSentToday(record.campaignId);
  if (sentToday >= dailyLimit) {
    return { skipped: true, reason: 'daily_limit' };
  }

  await store.updateQueueItem(item.id, { status: 'processing', attempts: (item.attempts || 0) + 1 });
  const from = settings.senderEmail
    ? `${settings.senderName || 'Najeeb'} <${settings.senderEmail}>`
    : settings.senderEmail;
  if (!from) {
    const err = new Error('OUTREACH_FROM_EMAIL / senderEmail is not configured.');
    err.status = 503;
    throw err;
  }

  try {
    const result = await sender.sendEmail({
      recipient: item.recipient,
      subject: item.subject,
      body: item.body,
      from,
      replyTo: settings.replyTo || settings.senderEmail,
    });
    await store.updateQueueItem(item.id, {
      status: 'sent',
      sentAt: new Date(),
      providerMessageId: result.messageId,
      error: null,
    });
    const followUpCount = item.kind === 'initial' ? 0 : item.kind === 'follow_up_1' ? 1 : 2;
    await store.updateRecord(item.recordId, {
      outreachStatus: 'sent',
      lastContactedAt: FieldValue.serverTimestamp(),
      followUpCount,
      lastEvent: 'email_sent',
      lastError: null,
    });
    await store.logEvent({ type: 'email_sent', recordId: item.recordId, campaignId: item.campaignId, queueId: item.id });
    outreachLog('email_sent', { recordId: item.recordId, kind: item.kind, testMode: item.testMode === true });

    if (item.kind === 'initial' || item.kind === 'follow_up_1') {
      await scheduleNextFollowUp(item, record, settings);
    }
    return { sent: true, messageId: result.messageId };
  } catch (err) {
    const temporary = isTemporarySendFailure(err);
    const attempts = (item.attempts || 0) + 1;
    const retryAt = new Date(Date.now() + Math.min(30 * 60 * 1000, 2 ** Math.min(attempts, 6) * 15_000));
    await store.updateQueueItem(item.id, {
      status: temporary && attempts < 5 ? 'pending' : 'failed',
      error: err.message || String(err),
      scheduledAt: temporary && attempts < 5 ? retryAt : undefined,
    });
    await store.setRecordError(item.recordId, err.message);
    if (!temporary || attempts >= 5) {
      await store.updateRecord(item.recordId, { outreachStatus: 'failed' });
    }
    await store.logEvent({ type: 'email_failed', recordId: item.recordId, campaignId: item.campaignId, queueId: item.id, message: err.message });
    outreachLog('email_failed', { recordId: item.recordId, temporary, attempts });
    throw err;
  }
}

async function scheduleNextFollowUp(item, record, settings) {
  if (!record.campaignId) return;
  const campaign = await store.getCampaign(record.campaignId).catch(() => null);
  if (!campaign?.followUpEnabled || campaign.status !== 'active') return;
  const nextKind = item.kind === 'initial' ? 'follow_up_1' : item.kind === 'follow_up_1' ? 'follow_up_2' : null;
  if (!nextKind) return;
  const days = nextKind === 'follow_up_1' ? campaign.followUp1DelayDays : campaign.followUp2DelayDays;
  const when = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  const followBody = nextKind === 'follow_up_1'
    ? `Hi ${record.business} team,\n\nJust bumping this in case it landed at a busy time. Happy to share a couple of website ideas if useful.\n\nBest,\n${settings.senderName || 'Najeeb'}`
    : `Hi ${record.business} team,\n\nI'll leave this here — if a better website or a clearer enquiry flow would help, I'm around.\n\nBest,\n${settings.senderName || 'Najeeb'}`;
  const followSubject = nextKind === 'follow_up_1'
    ? `Re: ${item.subject}`
    : `Last note for ${record.business}`;

  await store.updateRecord(item.recordId, { nextFollowUpAt: when });
  await store.enqueueEmail({
    leadId: record.sourceLeadId,
    recordId: record.id,
    campaignId: record.campaignId,
    recipient: item.recipient,
    intendedRecipient: item.intendedRecipient,
    subject: followSubject,
    body: appendUnsubscribeFooter(followBody, settings, (await store.getRecord(item.recordId)).unsubscribeToken),
    kind: nextKind,
    scheduledAt: when,
    testMode: item.testMode,
  });
  await store.logEvent({ type: 'follow_up_scheduled', recordId: item.recordId, campaignId: record.campaignId, message: nextKind });
  outreachLog('follow_up_scheduled', { recordId: item.recordId, kind: nextKind, days });
}

export async function drainQueue({ max = 5 } = {}) {
  const settings = await store.getSettings();
  const sender = createEmailSenderService();
  const due = await store.listDueQueue({ limit: max });
  const results = [];
  for (const item of due) {
    try {
      const result = await sendQueueItem(item, { sender, settings });
      results.push({ id: item.id, ...result });
      if (result?.reason === 'daily_limit') break;
      await new Promise((r) => setTimeout(r, settings.sendIntervalMs || 8000));
    } catch (err) {
      results.push({ id: item.id, error: err.message || String(err) });
    }
  }
  return results;
}

export async function applyProviderEvent({ messageId, type, email }) {
  const found = await store.findRecordByProviderMessageId(messageId);
  const record = found?.record;
  if (!record) {
    if (type === 'unsubscribed' && email) {
      await store.addUnsubscribe(email, { reason: 'provider' });
    }
    return null;
  }
  const map = {
    delivered: 'delivered',
    opened: 'opened',
    bounced: 'bounced',
    unsubscribed: 'unsubscribed',
    complained: 'unsubscribed',
  };
  const status = map[type];
  if (!status) return record;
  if (status === 'opened' && type !== 'opened') return record;
  const eventType = type === 'delivered' ? 'email_delivered'
    : type === 'opened' ? 'email_opened'
      : type === 'bounced' ? 'email_bounced'
        : 'unsubscribed';
  await store.updateRecord(record.id, {
    outreachStatus: status,
    unsubscribeStatus: status === 'unsubscribed',
    lastEvent: eventType,
  });
  if (status === 'unsubscribed' && (email || record.email)) {
    await store.addUnsubscribe(email || record.email, { recordId: record.id, reason: 'provider' });
    await cancelPendingForRecord(record.id, 'unsubscribed');
  }
  if (status === 'bounced') {
    await cancelPendingForRecord(record.id, 'bounced');
  }
  await store.logEvent({ type: eventType, recordId: record.id, campaignId: record.campaignId, queueId: found.queue?.id });
  return store.getRecord(record.id);
}

export { createEmailSenderService };
