/**
 * Firestore persistence for website-dev outreach. Source leads stay in
 * `websiteLeads` / `leads`; this module owns campaign, queue, event, and
 * per-lead outreach records so scan upserts never clobber pipeline state.
 */

import crypto from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';
import {
  CAMPAIGN_STATUSES,
  COLLECTIONS,
  DEFAULT_DAILY_LIMIT,
  DEFAULT_FOLLOW_UP_1_DAYS,
  DEFAULT_FOLLOW_UP_2_DAYS,
  EMAIL_SOURCES,
  EMAIL_VERIFY_RESULTS,
  EVENT_TYPES,
  FOLLOW_UP_KINDS,
  OUTREACH_STATUSES,
  PIPELINE_STATUSES,
  QUEUE_STATUSES,
  SETTINGS_DOC_ID,
  SOURCE_COLLECTIONS,
} from './constants.js';

function ts(value) {
  return value?.toDate?.()?.toISOString?.() || null;
}

function httpError(message, status = 400) {
  const err = new Error(message);
  err.status = status;
  return err;
}

export function recordId(sourceCollection, sourceLeadId) {
  return `${sourceCollection}_${sourceLeadId}`;
}

function assertEnum(value, allowed, field) {
  if (!allowed.includes(value)) {
    throw httpError(`${field} must be one of: ${allowed.join(', ')}`);
  }
}

function docToRecord(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    sourceCollection: d.sourceCollection,
    sourceLeadId: d.sourceLeadId,
    campaignId: d.campaignId || null,
    business: d.business || '',
    category: d.category || null,
    location: d.location || null,
    address: d.address || null,
    phone: d.phone || null,
    website: d.website || null,
    mapsUrl: d.mapsUrl || null,
    email: d.email || null,
    emails: d.emails || [],
    emailStatus: d.emailStatus || 'unknown',
    emailSource: d.emailSource || null,
    emailVerified: d.emailVerified === true,
    outreachStatus: OUTREACH_STATUSES.includes(d.outreachStatus) ? d.outreachStatus : 'not_processed',
    websiteAnalysisStatus: d.websiteAnalysisStatus || 'not_started',
    emailGenerationStatus: d.emailGenerationStatus || 'not_started',
    outreachApproved: d.outreachApproved === true,
    websiteAnalysis: d.websiteAnalysis || null,
    generatedSubject: d.generatedSubject || null,
    generatedBody: d.generatedBody || null,
    generatedAt: ts(d.generatedAt),
    aiModel: d.aiModel || null,
    lastContactedAt: ts(d.lastContactedAt),
    followUpCount: Number(d.followUpCount) || 0,
    nextFollowUpAt: ts(d.nextFollowUpAt),
    replyStatus: d.replyStatus || null,
    unsubscribeStatus: d.unsubscribeStatus === true,
    lastError: d.lastError || null,
    lastErrorAt: ts(d.lastErrorAt),
    lastEvent: d.lastEvent || null,
    createdAt: ts(d.createdAt),
    updatedAt: ts(d.updatedAt),
  };
}

function docToCampaign(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    name: d.name || '',
    description: d.description || '',
    status: CAMPAIGN_STATUSES.includes(d.status) ? d.status : 'draft',
    sourceCollection: d.sourceCollection || 'websiteLeads',
    filters: d.filters || {},
    dailyLimit: Number(d.dailyLimit) || DEFAULT_DAILY_LIMIT,
    followUpEnabled: d.followUpEnabled !== false,
    followUp1DelayDays: Number(d.followUp1DelayDays) || DEFAULT_FOLLOW_UP_1_DAYS,
    followUp2DelayDays: Number(d.followUp2DelayDays) || DEFAULT_FOLLOW_UP_2_DAYS,
    testMode: d.testMode === true,
    createdAt: ts(d.createdAt),
    updatedAt: ts(d.updatedAt),
    stats: d.stats || {},
  };
}

function docToQueueItem(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    leadId: d.leadId,
    campaignId: d.campaignId || null,
    recordId: d.recordId,
    recipient: d.recipient,
    intendedRecipient: d.intendedRecipient || d.recipient,
    subject: d.subject,
    body: d.body,
    kind: FOLLOW_UP_KINDS.includes(d.kind) ? d.kind : 'initial',
    status: QUEUE_STATUSES.includes(d.status) ? d.status : 'pending',
    scheduledAt: ts(d.scheduledAt),
    attempts: Number(d.attempts) || 0,
    sentAt: ts(d.sentAt),
    providerMessageId: d.providerMessageId || null,
    error: d.error || null,
    testMode: d.testMode === true,
    createdAt: ts(d.createdAt),
  };
}

function docToEvent(doc) {
  const d = doc.data() || {};
  return {
    id: doc.id,
    type: d.type,
    recordId: d.recordId || null,
    campaignId: d.campaignId || null,
    queueId: d.queueId || null,
    message: d.message || null,
    createdAt: ts(d.createdAt),
  };
}

export async function getSettings() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.settings).doc(SETTINGS_DOC_ID).get();
  const d = snap.data() || {};
  return {
    testMode: d.testMode === true,
    testEmail: d.testEmail || process.env.OUTREACH_TEST_EMAIL || '',
    senderName: d.senderName || process.env.OUTREACH_SENDER_NAME || 'Najeeb',
    senderEmail: d.senderEmail || process.env.OUTREACH_FROM_EMAIL || '',
    replyTo: d.replyTo || process.env.OUTREACH_REPLY_TO || '',
    defaultDailyLimit: Number(d.defaultDailyLimit) || DEFAULT_DAILY_LIMIT,
    sendIntervalMs: Number(d.sendIntervalMs) || Number(process.env.OUTREACH_SEND_INTERVAL_MS) || 8000,
    publicBaseUrl: d.publicBaseUrl || process.env.OUTREACH_PUBLIC_BASE_URL || '',
    senderConfigured: Boolean(process.env.RESEND_API_KEY?.trim() || process.env.SMTP_HOST?.trim()),
  };
}

export async function updateSettings(input = {}) {
  const db = getFirestore();
  const payload = { updatedAt: FieldValue.serverTimestamp() };
  if (input.testMode !== undefined) payload.testMode = Boolean(input.testMode);
  if (input.testEmail !== undefined) payload.testEmail = String(input.testEmail || '').trim();
  if (input.senderName !== undefined) payload.senderName = String(input.senderName || '').trim();
  if (input.senderEmail !== undefined) payload.senderEmail = String(input.senderEmail || '').trim();
  if (input.replyTo !== undefined) payload.replyTo = String(input.replyTo || '').trim();
  if (input.defaultDailyLimit !== undefined) payload.defaultDailyLimit = Math.max(1, Number(input.defaultDailyLimit) || DEFAULT_DAILY_LIMIT);
  if (input.sendIntervalMs !== undefined) payload.sendIntervalMs = Math.max(1000, Number(input.sendIntervalMs) || 8000);
  if (input.publicBaseUrl !== undefined) payload.publicBaseUrl = String(input.publicBaseUrl || '').trim();
  const ref = db.collection(COLLECTIONS.settings).doc(SETTINGS_DOC_ID);
  await ref.set(payload, { merge: true });
  return getSettings();
}

export async function logEvent({ type, recordId: rid, campaignId, queueId, message }) {
  if (!EVENT_TYPES.includes(type)) return;
  const db = getFirestore();
  await db.collection(COLLECTIONS.events).add({
    type,
    recordId: rid || null,
    campaignId: campaignId || null,
    queueId: queueId || null,
    message: message ? String(message).slice(0, 500) : null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

export async function getSourceLead(sourceCollection, sourceLeadId) {
  if (!SOURCE_COLLECTIONS.includes(sourceCollection)) {
    throw httpError(`sourceCollection must be one of: ${SOURCE_COLLECTIONS.join(', ')}`);
  }
  const db = getFirestore();
  const snap = await db.collection(sourceCollection).doc(sourceLeadId).get();
  if (!snap.exists) throw httpError('Lead not found', 404);
  const d = snap.data();
  return {
    dbId: snap.id,
    business: d.business || 'Unknown',
    category: d.category || null,
    location: d.location || null,
    address: d.address || null,
    phone: d.phone || null,
    website: d.website || null,
    mapsUrl: d.mapsUrl || null,
    email: d.email || null,
  };
}

export async function ensureRecord({ sourceCollection, sourceLeadId, campaignId = null }) {
  const lead = await getSourceLead(sourceCollection, sourceLeadId);
  const db = getFirestore();
  const id = recordId(sourceCollection, sourceLeadId);
  const ref = db.collection(COLLECTIONS.records).doc(id);
  const snap = await ref.get();
  const base = {
    sourceCollection,
    sourceLeadId,
    business: lead.business,
    category: lead.category,
    location: lead.location,
    address: lead.address,
    phone: lead.phone,
    website: lead.website,
    mapsUrl: lead.mapsUrl,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (campaignId) base.campaignId = campaignId;
  if (!snap.exists) {
    await ref.set({
      ...base,
      email: lead.email || null,
      emails: [],
      emailStatus: 'unknown',
      emailSource: lead.email ? 'manual' : null,
      emailVerified: false,
      outreachStatus: 'not_processed',
      websiteAnalysisStatus: 'not_started',
      emailGenerationStatus: 'not_started',
      outreachApproved: false,
      followUpCount: 0,
      unsubscribeStatus: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } else {
    await ref.set(base, { merge: true });
  }
  return getRecord(id);
}

export async function getRecord(id) {
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.records).doc(id).get();
  if (!snap.exists) throw httpError('Outreach record not found', 404);
  return docToRecord(snap);
}

export async function updateRecord(id, patch) {
  const db = getFirestore();
  const ref = db.collection(COLLECTIONS.records).doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw httpError('Outreach record not found', 404);
  const payload = { updatedAt: FieldValue.serverTimestamp() };
  const assign = (key, value) => {
    payload[key] = value;
  };

  if (patch.email !== undefined) assign('email', patch.email ? String(patch.email).trim().toLowerCase() : null);
  if (patch.emails !== undefined) assign('emails', patch.emails);
  if (patch.emailStatus !== undefined) {
    assertEnum(patch.emailStatus, EMAIL_VERIFY_RESULTS, 'emailStatus');
    assign('emailStatus', patch.emailStatus);
  }
  if (patch.emailSource !== undefined) {
    if (patch.emailSource && !EMAIL_SOURCES.includes(patch.emailSource)) {
      throw httpError(`emailSource must be one of: ${EMAIL_SOURCES.join(', ')}`);
    }
    assign('emailSource', patch.emailSource);
  }
  if (patch.emailVerified !== undefined) assign('emailVerified', Boolean(patch.emailVerified));
  if (patch.outreachStatus !== undefined) {
    assertEnum(patch.outreachStatus, OUTREACH_STATUSES, 'outreachStatus');
    assign('outreachStatus', patch.outreachStatus);
  }
  if (patch.websiteAnalysisStatus !== undefined) {
    assertEnum(patch.websiteAnalysisStatus, PIPELINE_STATUSES, 'websiteAnalysisStatus');
    assign('websiteAnalysisStatus', patch.websiteAnalysisStatus);
  }
  if (patch.emailGenerationStatus !== undefined) {
    assertEnum(patch.emailGenerationStatus, PIPELINE_STATUSES, 'emailGenerationStatus');
    assign('emailGenerationStatus', patch.emailGenerationStatus);
  }
  if (patch.outreachApproved !== undefined) assign('outreachApproved', Boolean(patch.outreachApproved));
  if (patch.websiteAnalysis !== undefined) assign('websiteAnalysis', patch.websiteAnalysis);
  if (patch.generatedSubject !== undefined) assign('generatedSubject', patch.generatedSubject);
  if (patch.generatedBody !== undefined) assign('generatedBody', patch.generatedBody);
  if (patch.generatedAt !== undefined) assign('generatedAt', patch.generatedAt);
  if (patch.aiModel !== undefined) assign('aiModel', patch.aiModel);
  if (patch.lastContactedAt !== undefined) assign('lastContactedAt', patch.lastContactedAt);
  if (patch.followUpCount !== undefined) assign('followUpCount', Number(patch.followUpCount) || 0);
  if (patch.nextFollowUpAt !== undefined) assign('nextFollowUpAt', patch.nextFollowUpAt);
  if (patch.replyStatus !== undefined) assign('replyStatus', patch.replyStatus);
  if (patch.unsubscribeStatus !== undefined) assign('unsubscribeStatus', Boolean(patch.unsubscribeStatus));
  if (patch.campaignId !== undefined) assign('campaignId', patch.campaignId);
  if (patch.lastError !== undefined) assign('lastError', patch.lastError);
  if (patch.lastErrorAt !== undefined) assign('lastErrorAt', patch.lastErrorAt);
  if (patch.lastEvent !== undefined) assign('lastEvent', patch.lastEvent);
  if (patch.website !== undefined) assign('website', patch.website);
  if (patch.unsubscribeToken !== undefined) assign('unsubscribeToken', patch.unsubscribeToken);

  await ref.set(payload, { merge: true });
  const record = await getRecord(id);
  await syncStatusToSource(record);
  return record;
}

async function syncStatusToSource(record) {
  if (!record?.sourceCollection || !record?.sourceLeadId || !record.outreachStatus) return;
  try {
    const db = getFirestore();
    const payload = { emailOutreachStatus: record.outreachStatus };
    if (record.email) payload.email = record.email;
    if (record.outreachStatus === 'sent' || record.outreachStatus === 'delivered' || record.outreachStatus === 'opened') {
      payload.emailSentAt = FieldValue.serverTimestamp();
    }
    await db.collection(record.sourceCollection).doc(record.sourceLeadId).set(payload, { merge: true });
  } catch (_) {
    // Source lead may have been deleted; outreach record still stands.
  }
}

export async function setRecordError(id, error) {
  return updateRecord(id, {
    lastError: String(error || 'Unknown error').slice(0, 500),
    lastErrorAt: FieldValue.serverTimestamp(),
  });
}

export async function listRecords({
  outreachStatus,
  emailVerified,
  readyForReview,
  campaignId,
  sourceCollection,
  limit = 50,
  cursor,
} = {}) {
  const db = getFirestore();
  const lim = Math.min(Number(limit) || 50, 200);
  let q = db.collection(COLLECTIONS.records);

  if (sourceCollection) {
    q = q.where('sourceCollection', '==', sourceCollection).limit(400);
  } else if (readyForReview) {
    q = q.where('emailGenerationStatus', '==', 'completed').limit(400);
  } else if (campaignId) {
    q = q.where('campaignId', '==', campaignId).limit(200);
  } else if (outreachStatus) {
    q = q.where('outreachStatus', '==', outreachStatus).limit(200);
  } else if (emailVerified === true || emailVerified === false) {
    q = q.where('emailVerified', '==', emailVerified).limit(200);
  } else {
    q = q.orderBy('updatedAt', 'desc').limit(lim + 1);
    if (cursor) {
      const cursorSnap = await db.collection(COLLECTIONS.records).doc(String(cursor)).get();
      if (cursorSnap.exists) q = q.startAfter(cursorSnap);
    }
  }
  const snap = await q.get();
  let records = snap.docs.map(docToRecord);
  records.sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || '')));
  if (readyForReview) {
    records = records.filter((r) => !r.outreachApproved);
  }
  if (campaignId && readyForReview) {
    records = records.filter((r) => r.campaignId === campaignId);
  }
  if (outreachStatus && sourceCollection) {
    records = records.filter((r) => r.outreachStatus === outreachStatus);
  }
  const page = records.slice(0, lim);
  const unfiltered = !readyForReview && !campaignId && !outreachStatus && emailVerified !== true && emailVerified !== false;
  return {
    records: page,
    nextCursor: unfiltered && snap.docs.length > lim ? snap.docs[lim].id : null,
  };
}

export async function createCampaign(input) {
  const name = String(input.name || '').trim();
  if (!name) throw httpError('name is required');
  const sourceCollection = input.sourceCollection || 'websiteLeads';
  assertEnum(sourceCollection, SOURCE_COLLECTIONS, 'sourceCollection');
  const db = getFirestore();
  const ref = db.collection(COLLECTIONS.campaigns).doc();
  await ref.set({
    name,
    description: String(input.description || '').trim(),
    status: CAMPAIGN_STATUSES.includes(input.status) ? input.status : 'draft',
    sourceCollection,
    filters: {
      category: input.filters?.category || null,
      location: input.filters?.location || null,
      hasWebsite: input.filters?.hasWebsite ?? null,
      hasEmail: input.filters?.hasEmail ?? null,
      emailVerified: input.filters?.emailVerified ?? null,
      outreachStatus: input.filters?.outreachStatus || null,
    },
    dailyLimit: Math.max(1, Number(input.dailyLimit) || DEFAULT_DAILY_LIMIT),
    followUpEnabled: input.followUpEnabled !== false,
    followUp1DelayDays: Math.max(1, Number(input.followUp1DelayDays) || DEFAULT_FOLLOW_UP_1_DAYS),
    followUp2DelayDays: Math.max(1, Number(input.followUp2DelayDays) || DEFAULT_FOLLOW_UP_2_DAYS),
    testMode: input.testMode === true,
    stats: {},
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return docToCampaign(await ref.get());
}

export async function getCampaign(id) {
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.campaigns).doc(id).get();
  if (!snap.exists) throw httpError('Campaign not found', 404);
  return docToCampaign(snap);
}

export async function listCampaigns() {
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.campaigns).orderBy('createdAt', 'desc').limit(200).get();
  return snap.docs.map(docToCampaign);
}

export async function updateCampaign(id, input) {
  const db = getFirestore();
  const ref = db.collection(COLLECTIONS.campaigns).doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw httpError('Campaign not found', 404);
  const payload = { updatedAt: FieldValue.serverTimestamp() };
  if (input.name !== undefined) payload.name = String(input.name).trim();
  if (input.description !== undefined) payload.description = String(input.description).trim();
  if (input.status !== undefined) {
    assertEnum(input.status, CAMPAIGN_STATUSES, 'status');
    payload.status = input.status;
  }
  if (input.dailyLimit !== undefined) payload.dailyLimit = Math.max(1, Number(input.dailyLimit) || DEFAULT_DAILY_LIMIT);
  if (input.followUpEnabled !== undefined) payload.followUpEnabled = Boolean(input.followUpEnabled);
  if (input.followUp1DelayDays !== undefined) payload.followUp1DelayDays = Math.max(1, Number(input.followUp1DelayDays) || DEFAULT_FOLLOW_UP_1_DAYS);
  if (input.followUp2DelayDays !== undefined) payload.followUp2DelayDays = Math.max(1, Number(input.followUp2DelayDays) || DEFAULT_FOLLOW_UP_2_DAYS);
  if (input.testMode !== undefined) payload.testMode = Boolean(input.testMode);
  if (input.filters !== undefined) payload.filters = input.filters;
  await ref.set(payload, { merge: true });
  return docToCampaign(await ref.get());
}

export function leadMatchesFilters(lead, filters = {}) {
  if (filters.category && String(lead.category || '') !== String(filters.category)) return false;
  if (filters.location) {
    const loc = String(lead.location || '').toLowerCase();
    if (!loc.includes(String(filters.location).toLowerCase())) return false;
  }
  if (filters.hasWebsite === true && !lead.website) return false;
  if (filters.hasWebsite === false && lead.website) return false;
  if (filters.hasEmail === true && !lead.email) return false;
  if (filters.hasEmail === false && lead.email) return false;
  return true;
}

export async function iterateSourceLeads(sourceCollection, { pageSize = 200 } = {}) {
  const db = getFirestore();
  let last = null;
  const out = [];
  // Caller consumes via async iterator-style loop in enrollCampaign.
  async function nextPage() {
    let q = db.collection(sourceCollection).orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return [];
    last = snap.docs[snap.docs.length - 1];
    return snap.docs.map((doc) => {
      const d = doc.data();
      return {
        dbId: doc.id,
        business: d.business,
        category: d.category,
        location: d.location,
        address: d.address,
        phone: d.phone,
        website: d.website || null,
        mapsUrl: d.mapsUrl || null,
        email: d.email || null,
      };
    });
  }
  return { nextPage, _unused: out };
}

export async function listLeadsInRange(sourceCollection, from, to) {
  const start = Math.max(1, Number(from) || 1);
  const end = Math.max(start, Number(to) || start);
  const need = end - start + 1;
  const skip = start - 1;
  const { nextPage } = await iterateSourceLeads(sourceCollection, { pageSize: 200 });
  const picked = [];
  let seen = 0;
  while (picked.length < need) {
    const page = await nextPage();
    if (!page.length) break;
    for (const lead of page) {
      seen += 1;
      if (seen <= skip) continue;
      picked.push(lead);
      if (picked.length >= need) break;
    }
  }
  return { leads: picked, from: start, to: end, scanned: seen };
}

export async function isUnsubscribed(email) {
  if (!email) return false;
  const db = getFirestore();
  const key = crypto.createHash('sha256').update(String(email).trim().toLowerCase()).digest('hex');
  const snap = await db.collection(COLLECTIONS.unsubscribes).doc(key).get();
  return snap.exists;
}

export async function addUnsubscribe(email, { recordId: rid, reason } = {}) {
  const normalized = String(email || '').trim().toLowerCase();
  if (!normalized) throw httpError('email is required');
  const db = getFirestore();
  const key = crypto.createHash('sha256').update(normalized).digest('hex');
  await db.collection(COLLECTIONS.unsubscribes).doc(key).set({
    email: normalized,
    recordId: rid || null,
    reason: reason || 'recipient_opt_out',
    createdAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

export async function findRecordByUnsubscribeToken(token) {
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.records).where('unsubscribeToken', '==', token).limit(1).get();
  if (snap.empty) return null;
  return docToRecord(snap.docs[0]);
}

export async function enqueueEmail(input) {
  const db = getFirestore();
  const ref = db.collection(COLLECTIONS.queue).doc();
  const scheduledAt = input.scheduledAt instanceof Date ? input.scheduledAt : new Date(input.scheduledAt || Date.now());
  await ref.set({
    leadId: input.leadId,
    recordId: input.recordId,
    campaignId: input.campaignId || null,
    recipient: input.recipient,
    intendedRecipient: input.intendedRecipient || input.recipient,
    subject: input.subject,
    body: input.body,
    kind: FOLLOW_UP_KINDS.includes(input.kind) ? input.kind : 'initial',
    status: 'pending',
    scheduledAt,
    attempts: 0,
    sentAt: null,
    providerMessageId: null,
    error: null,
    testMode: input.testMode === true,
    createdAt: FieldValue.serverTimestamp(),
  });
  return docToQueueItem(await ref.get());
}

export async function listDueQueue({ limit = 10 } = {}) {
  const db = getFirestore();
  // Equality-only so this works without a composite index. The send
  // queue stays small; filter/sort due items in memory.
  const snap = await db
    .collection(COLLECTIONS.queue)
    .where('status', '==', 'pending')
    .limit(100)
    .get();
  const now = Date.now();
  const due = snap.docs
    .map(docToQueueItem)
    .filter((item) => {
      const at = item.scheduledAt ? Date.parse(item.scheduledAt) : 0;
      return Number.isFinite(at) && at <= now;
    })
    .sort((a, b) => Date.parse(a.scheduledAt) - Date.parse(b.scheduledAt));
  return due.slice(0, Math.min(Number(limit) || 10, 25));
}

export async function getQueueItem(id) {
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.queue).doc(id).get();
  if (!snap.exists) throw httpError('Queue item not found', 404);
  return docToQueueItem(snap);
}

export async function updateQueueItem(id, patch) {
  const db = getFirestore();
  const payload = { ...patch };
  if (patch.status) assertEnum(patch.status, QUEUE_STATUSES, 'status');
  await db.collection(COLLECTIONS.queue).doc(id).set(payload, { merge: true });
  return getQueueItem(id);
}

export async function countSentToday(campaignId) {
  const db = getFirestore();
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  const snap = await db.collection(COLLECTIONS.queue).where('status', '==', 'sent').limit(500).get();
  let count = 0;
  for (const doc of snap.docs) {
    const item = docToQueueItem(doc);
    if (campaignId && item.campaignId !== campaignId) continue;
    const sent = item.sentAt ? Date.parse(item.sentAt) : 0;
    if (sent >= start.getTime()) count += 1;
  }
  return count;
}

export async function listQueue({ status, limit = 50 } = {}) {
  const db = getFirestore();
  const snap = await db
    .collection(COLLECTIONS.queue)
    .orderBy('createdAt', 'desc')
    .limit(200)
    .get();
  let items = snap.docs.map(docToQueueItem);
  if (status) items = items.filter((i) => i.status === status);
  return items.slice(0, Math.min(Number(limit) || 50, 200));
}

export async function listEvents({ recordId: rid, limit = 50 } = {}) {
  const db = getFirestore();
  const cap = Math.min(Number(limit) || 50, 200);
  let q = db.collection(COLLECTIONS.events);
  if (rid) q = q.where('recordId', '==', rid);
  const snap = await q.limit(200).get();
  return snap.docs
    .map(docToEvent)
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')))
    .slice(0, cap);
}

export async function aggregateStats() {
  const db = getFirestore();
  const records = db.collection(COLLECTIONS.records);
  const [totalSnap, verifiedSnap, reviewSnap, approvedSnap, sentSnap, unsubSnap] = await Promise.all([
    records.count().get(),
    records.where('emailVerified', '==', true).count().get(),
    records.where('emailGenerationStatus', '==', 'completed').count().get(),
    records.where('outreachApproved', '==', true).count().get(),
    records.where('outreachStatus', '==', 'sent').count().get(),
    records.where('unsubscribeStatus', '==', true).count().get(),
  ]);

  const countStatus = async (status) => {
    const snap = await records.where('outreachStatus', '==', status).count().get();
    return snap.data().count ?? 0;
  };

  const [queued, delivered, opened, replied, interested, bounced, failed, emailFound] = await Promise.all([
    countStatus('queued'),
    countStatus('delivered'),
    countStatus('opened'),
    countStatus('replied'),
    countStatus('interested'),
    countStatus('bounced'),
    countStatus('failed'),
    countStatus('email_found'),
  ]);

  const [queuePending, queueSent, queueFailed] = await Promise.all([
    db.collection(COLLECTIONS.queue).where('status', '==', 'pending').count().get(),
    db.collection(COLLECTIONS.queue).where('status', '==', 'sent').count().get(),
    db.collection(COLLECTIONS.queue).where('status', '==', 'failed').count().get(),
  ]);

  return {
    totalRecords: totalSnap.data().count ?? 0,
    emailsFound: emailFound + (verifiedSnap.data().count ?? 0),
    verifiedEmails: verifiedSnap.data().count ?? 0,
    readyForReview: reviewSnap.data().count ?? 0,
    approved: approvedSnap.data().count ?? 0,
    queued: queued + (queuePending.data().count ?? 0),
    sent: sentSnap.data().count ?? queueSent.data().count ?? 0,
    delivered,
    opened,
    replies: replied,
    interested,
    bounced,
    unsubscribed: unsubSnap.data().count ?? 0,
    failed: failed + (queueFailed.data().count ?? 0),
  };
}

export async function campaignStats(campaignId) {
  const db = getFirestore();
  const records = db.collection(COLLECTIONS.records).where('campaignId', '==', campaignId);
  const countWhere = async (field, value) => {
    const snap = await records.where(field, '==', value).count().get();
    return snap.data().count ?? 0;
  };
  const [leads, approved, sent, replies, interested] = await Promise.all([
    records.count().get(),
    countWhere('outreachApproved', true),
    countWhere('outreachStatus', 'sent'),
    countWhere('outreachStatus', 'replied'),
    countWhere('outreachStatus', 'interested'),
  ]);
  return {
    leads: leads.data().count ?? 0,
    approved,
    sent,
    replies,
    interested,
  };
}

export async function findRecordByProviderMessageId(messageId) {
  if (!messageId) return null;
  const db = getFirestore();
  const snap = await db.collection(COLLECTIONS.queue).where('providerMessageId', '==', messageId).limit(1).get();
  if (snap.empty) return null;
  const item = docToQueueItem(snap.docs[0]);
  if (!item.recordId) return { queue: item, record: null };
  return { queue: item, record: await getRecord(item.recordId) };
}
