import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';
import * as store from '../services/outreach/outreachStore.js';
import {
  discoverEmail,
  verifyEmail,
  analyzeRecordWebsite,
  generateEmail,
  processLeadPipeline,
  approveAndQueue,
  rejectRecord,
  markStatus,
  applyProviderEvent,
  drainQueue,
} from '../services/outreach/outreachPipeline.js';
import {
  startCampaignPipeline,
  startRangeJob,
  getOutreachJobSnapshot,
  cancelOutreachJob,
  enrollCampaign,
} from '../services/outreach/outreachOrchestrator.js';
import { getWebsiteLeadCount } from '../services/websiteLeadStore.js';
import { OUTREACH_STATUSES } from '../services/outreach/constants.js';

function fail(res, err) {
  return res.status(err.status || 500).json({ error: err.message || 'Outreach error' });
}

async function syncEmailToSource(record) {
  if (!record?.email || !record.sourceCollection || !record.sourceLeadId) return;
  const db = getFirestore();
  await db.collection(record.sourceCollection).doc(record.sourceLeadId).set(
    { email: record.email, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

export async function getDashboard(req, res) {
  try {
    const [stats, settings, websiteLeadCount, campaigns] = await Promise.all([
      store.aggregateStats(),
      store.getSettings(),
      getWebsiteLeadCount().catch(() => 0),
      store.listCampaigns().catch(() => []),
    ]);
    return res.json({
      stats: { ...stats, totalWebsiteLeads: websiteLeadCount },
      settings,
      campaigns,
      job: getOutreachJobSnapshot(),
    });
  } catch (err) {
    return fail(res, err);
  }
}

export async function getAnalytics(_req, res) {
  try {
    const [stats, campaigns, settings] = await Promise.all([
      store.aggregateStats(),
      store.listCampaigns(),
      store.getSettings(),
    ]);
    const rows = await Promise.all(
      campaigns.map(async (c) => ({ ...c, stats: await store.campaignStats(c.id) })),
    );
    const sent = stats.sent || 0;
    const delivered = stats.delivered || 0;
    const rates = {
      deliveryRate: sent ? delivered / sent : 0,
      bounceRate: sent ? (stats.bounced || 0) / sent : 0,
      openRate: delivered || sent ? (stats.opened || 0) / (delivered || sent) : 0,
      replyRate: sent ? (stats.replies || 0) / sent : 0,
      interestedRate: sent ? (stats.interested || 0) / sent : 0,
    };
    return res.json({ stats, rates, campaigns: rows, testMode: settings.testMode });
  } catch (err) {
    return fail(res, err);
  }
}

export async function getSettings(_req, res) {
  try {
    return res.json({ settings: await store.getSettings() });
  } catch (err) {
    return fail(res, err);
  }
}

export async function patchSettings(req, res) {
  try {
    return res.json({ settings: await store.updateSettings(req.body || {}) });
  } catch (err) {
    return fail(res, err);
  }
}

export async function listRecords(req, res) {
  try {
    const result = await store.listRecords({
      outreachStatus: req.query.outreachStatus,
      campaignId: req.query.campaignId,
      sourceCollection: req.query.sourceCollection,
      emailVerified: req.query.emailVerified === 'true' ? true : req.query.emailVerified === 'false' ? false : undefined,
      readyForReview: req.query.readyForReview === 'true',
      limit: req.query.limit,
      cursor: req.query.cursor,
    });
    return res.json(result);
  } catch (err) {
    return fail(res, err);
  }
}

export async function ensureAndGetRecord(req, res) {
  try {
    const { sourceCollection, sourceLeadId } = req.body || {};
    const record = await store.ensureRecord({ sourceCollection, sourceLeadId, campaignId: req.body?.campaignId });
    return res.json({ record });
  } catch (err) {
    return fail(res, err);
  }
}

export async function getRecord(req, res) {
  try {
    const record = await store.getRecord(req.params.id);
    const events = await store.listEvents({ recordId: record.id, limit: 50 });
    return res.json({ record, events });
  } catch (err) {
    return fail(res, err);
  }
}

export async function patchRecord(req, res) {
  try {
    const body = req.body || {};
    const record = await store.updateRecord(req.params.id, {
      generatedSubject: body.generatedSubject,
      generatedBody: body.generatedBody,
      email: body.email,
      emailSource: body.email ? 'manual' : undefined,
      website: body.website,
      outreachStatus: body.outreachStatus,
    });
    if (body.email) await syncEmailToSource(record);
    return res.json({ record });
  } catch (err) {
    return fail(res, err);
  }
}

async function runStep(req, res, fn) {
  try {
    const force = req.body?.force === true;
    const record = await fn(req.params.id, { force });
    if (record.email) await syncEmailToSource(record).catch(() => {});
    return res.json({ record });
  } catch (err) {
    return fail(res, err);
  }
}

export async function postDiscover(req, res) {
  return runStep(req, res, discoverEmail);
}

export async function postVerify(req, res) {
  return runStep(req, res, verifyEmail);
}

export async function postAnalyze(req, res) {
  return runStep(req, res, analyzeRecordWebsite);
}

export async function postGenerate(req, res) {
  return runStep(req, res, generateEmail);
}

export async function postProcess(req, res) {
  try {
    const force = req.body?.force === true;
    const autoSend = req.body?.autoSend === true;
    const record = await processLeadPipeline(req.params.id, { force, autoSend });
    if (record.email) await syncEmailToSource(record).catch(() => {});
    return res.json({ record });
  } catch (err) {
    return fail(res, err);
  }
}

export async function postApprove(req, res) {
  try {
    const result = await approveAndQueue(req.params.id, {
      subject: req.body?.subject,
      body: req.body?.body,
    });
    return res.json(result);
  } catch (err) {
    return fail(res, err);
  }
}

export async function postReject(req, res) {
  try {
    return res.json({ record: await rejectRecord(req.params.id) });
  } catch (err) {
    return fail(res, err);
  }
}

export async function postStatus(req, res) {
  try {
    const status = req.body?.outreachStatus;
    if (!OUTREACH_STATUSES.includes(status)) {
      return res.status(400).json({ error: `outreachStatus must be one of: ${OUTREACH_STATUSES.join(', ')}` });
    }
    return res.json({ record: await markStatus(req.params.id, status) });
  } catch (err) {
    return fail(res, err);
  }
}

export async function listCampaigns(_req, res) {
  try {
    const campaigns = await store.listCampaigns();
    const withStats = await Promise.all(
      campaigns.map(async (c) => ({ ...c, stats: await store.campaignStats(c.id) })),
    );
    return res.json({ campaigns: withStats });
  } catch (err) {
    return fail(res, err);
  }
}

export async function createCampaign(req, res) {
  try {
    const campaign = await store.createCampaign(req.body || {});
    return res.json({ campaign });
  } catch (err) {
    return fail(res, err);
  }
}

export async function patchCampaign(req, res) {
  try {
    return res.json({ campaign: await store.updateCampaign(req.params.id, req.body || {}) });
  } catch (err) {
    return fail(res, err);
  }
}

export async function postEnrollCampaign(req, res) {
  try {
    const result = await enrollCampaign(req.params.id, { maxLeads: req.body?.maxLeads });
    return res.json(result);
  } catch (err) {
    return fail(res, err);
  }
}

export async function postStartCampaign(req, res) {
  try {
    const snapshot = startCampaignPipeline({
      campaignId: req.params.id,
      force: req.body?.force === true,
      batchSize: req.body?.batchSize,
    });
    return res.status(202).json({ job: snapshot });
  } catch (err) {
    return fail(res, err);
  }
}

export async function postRun(req, res) {
  try {
    const snapshot = startRangeJob({
      kind: req.body?.kind,
      from: req.body?.from,
      to: req.body?.to,
      sourceCollection: req.body?.sourceCollection || 'websiteLeads',
      force: req.body?.force === true,
    });
    return res.status(202).json({ job: snapshot });
  } catch (err) {
    return fail(res, err);
  }
}

export async function getJob(_req, res) {
  return res.json({ job: getOutreachJobSnapshot() });
}

export async function postCancelJob(_req, res) {
  return res.json({ job: cancelOutreachJob() });
}

export async function postDrainQueue(_req, res) {
  try {
    const results = await drainQueue({ max: 5 });
    return res.json({ results });
  } catch (err) {
    return fail(res, err);
  }
}

export async function getQueue(req, res) {
  try {
    const items = await store.listQueue({ status: req.query.status, limit: req.query.limit });
    return res.json({ items });
  } catch (err) {
    return fail(res, err);
  }
}

export async function postWebhook(req, res) {
  try {
    const type = req.body?.type || req.body?.event;
    const messageId = req.body?.data?.email_id || req.body?.messageId || req.body?.id;
    const email = req.body?.data?.to?.[0] || req.body?.email;
    const record = await applyProviderEvent({ messageId, type, email });
    return res.json({ ok: true, record });
  } catch (err) {
    return fail(res, err);
  }
}

export async function getUnsubscribe(req, res) {
  try {
    const token = String(req.query.t || req.query.token || '').trim();
    if (!token) return res.status(400).send('Missing unsubscribe token.');
    const record = await store.findRecordByUnsubscribeToken(token);
    if (!record) return res.status(404).send('This unsubscribe link is not valid.');
    if (record.email) await store.addUnsubscribe(record.email, { recordId: record.id, reason: 'link' });
    await markStatus(record.id, 'unsubscribed');
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    return res.send(`<!doctype html><html><body style="font-family:sans-serif;padding:40px">
      <h1>You have been unsubscribed</h1>
      <p>You will not receive further campaign emails at this address.</p>
    </body></html>`);
  } catch (err) {
    return fail(res, err);
  }
}
