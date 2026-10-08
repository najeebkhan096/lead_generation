/**
 * Firestore-backed WhatsApp chat logic. All writes to outreach messages go
 * through here (Admin SDK); clients only read.
 *
 *   outreachLeads/{leadId}                       leadId = `${ownerId}_${phoneDigits}`
 *   outreachConversations/{leadId}               ownerId, leadId, phoneNumber, lastInboundAt, lastOutboundAt
 *   outreachConversations/{leadId}/messages/{id}
 */
import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getFirestore, getStorageBucket } from '../firebase.js';
import {
  HttpError, MAX_MEDIA_BYTES, MAX_TEXT_LENGTH, baseMime, describeTwilioError, extForMime, isValidE164,
  isWindowOpen, leadIdFor, mapTwilioStatus, messageTypeForMime, nextStatus, normalizePhone, previewFor,
  validateMediaMeta,
} from './validation.js';
import { VOICE_SOURCE_EXTS, VOICE_SOURCE_MIMES, transcodeToOggOpus } from './voice.js';
import {
  assertTwilioConfigured, basicAuth, createTwilioMessage, fetchTemplateBody, fetchTwilioMessage, listTwilioMedia, listTwilioMessages,
  twilioConfig,
} from './twilioClient.js';

const LEADS = 'outreachLeads';
const CONVS = 'outreachConversations';
const log = (...a) => console.log('[twilio-chat]', ...a);

const db = () => getFirestore();
const msgsOf = (conversationId) => db().collection(CONVS).doc(conversationId).collection('messages');

// ---- leads -----------------------------------------------------------------

export async function loadOwnedLead(uid, leadId) {
  const snap = await db().collection(LEADS).doc(String(leadId ?? '')).get();
  if (!snap.exists) throw new HttpError(404, 'Lead not found.', 'LEAD_NOT_FOUND');
  const lead = snap.data();
  if (lead.ownerId !== uid) throw new HttpError(403, 'Not your lead.', 'FORBIDDEN');
  if (!isValidE164(lead.phoneNumber)) throw new HttpError(400, 'Lead has an invalid phone number.', 'INVALID_PHONE');
  return { id: snap.id, ...lead };
}

async function loadConversation(conversationId) {
  const snap = await db().collection(CONVS).doc(conversationId).get();
  return snap.exists ? snap.data() : null;
}

/** Creates the lead + conversation docs if missing. Idempotent. */
/** Free-form facts about the business (category, address, ...): short strings only. */
function cleanDetails(details) {
  const out = {};
  if (!details || typeof details !== 'object' || Array.isArray(details)) return out;
  for (const [k, v] of Object.entries(details).slice(0, 12)) {
    const key = String(k).trim().slice(0, 40);
    const val = String(v ?? '').trim().slice(0, 500);
    if (key && val && !key.includes('.')) out[key] = val;
  }
  return out;
}

export async function ensureLead({ ownerId, name, businessName = '', phoneNumber, details }) {
  const phone = normalizePhone(phoneNumber);
  if (!isValidE164(phone)) throw new HttpError(400, 'Phone must be E.164 (+countrycode…).', 'INVALID_PHONE');
  const id = leadIdFor(ownerId, phone);
  const leadRef = db().collection(LEADS).doc(id);
  const convRef = db().collection(CONVS).doc(id);
  const clean = cleanDetails(details);
  const created = await db().runTransaction(async (tx) => {
    const snap = await tx.get(leadRef);
    if (snap.exists) {
      // Fill in what an earlier import (phone number only) could not know.
      const cur = snap.data();
      const patch = {};
      if (businessName && !cur.businessName) patch.businessName = businessName;
      if (name && (!cur.name || cur.name === cur.phoneNumber)) patch.name = name;
      if (Object.keys(clean).length && !cur.details) patch.details = clean;
      if (Object.keys(patch).length) tx.update(leadRef, patch);
      return false;
    }
    const now = FieldValue.serverTimestamp();
    tx.set(leadRef, {
      id, ownerId, name: name || phone, businessName, phoneNumber: phone, profileImage: null, details: clean,
      createdAt: now, updatedAt: now, lastMessage: '', lastMessageType: null, lastMessageAt: null, unreadCount: 0,
    });
    tx.set(convRef, { id, ownerId, leadId: id, phoneNumber: phone, lastInboundAt: null, lastOutboundAt: null, createdAt: now }, { merge: true });
    return true;
  });
  return { id, created };
}

// ---- outbound --------------------------------------------------------------

function assertText(body) {
  const text = String(body ?? '').trim();
  if (text.length > MAX_TEXT_LENGTH) throw new HttpError(400, `Message too long (max ${MAX_TEXT_LENGTH}).`, 'TEXT_TOO_LONG');
  return text;
}

function assertMessageId(id) {
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(String(id ?? ''))) throw new HttpError(400, 'Invalid messageId.', 'BAD_MESSAGE_ID');
  return id;
}

async function assertWindowOpen(conversationId) {
  const conv = await loadConversation(conversationId);
  const ms = conv?.lastInboundAt?.toMillis?.();
  if (!isWindowOpen(ms)) {
    throw new HttpError(409, 'The 24-hour WhatsApp window is closed. Send an approved template first.', 'WINDOW_CLOSED');
  }
}

/**
 * Validates an uploaded Storage object belongs to this user/message and is a
 * legal WhatsApp media file; returns normalised media metadata.
 */
async function verifyStoredMedia({ uid, conversationId, messageId, media }) {
  const storagePath = String(media?.storagePath ?? '');
  const prefix = `outreach_media/${uid}/${conversationId}/${messageId}/`;
  if (!storagePath.startsWith(prefix) || storagePath.includes('..') || storagePath.length > 300) {
    throw new HttpError(400, 'Media path is not allowed.', 'BAD_MEDIA_PATH');
  }
  const file = getStorageBucket().file(storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new HttpError(400, 'Uploaded file was not found in storage.', 'MEDIA_NOT_FOUND');
  const [meta] = await file.getMetadata();
  const fileName = storagePath.slice(prefix.length);
  const size = Number(meta.size);
  const mimeType = baseMime(meta.contentType);
  if (media.mimeType && baseMime(media.mimeType) !== mimeType) {
    throw new HttpError(415, 'Declared and stored file types differ.', 'MIME_MISMATCH');
  }
  const durationMs = media.durationMs ? { durationMs: Math.round(Number(media.durationMs)) || null } : {};
  if (media.voice === true) return voiceNote({ file, storagePath, prefix, mimeType, fileName, size, durationMs });
  const { type } = validateMediaMeta({ mimeType, fileName, size });
  return { type, file, doc: { storagePath, mimeType, fileName, size, ...durationMs } };
}

/**
 * A recorded voice note arrives as AAC/m4a; WhatsApp plays only OGG/Opus natively, so
 * convert it, store the .ogg next to the original and send that. `playbackPath` keeps the
 * original so the app (iOS cannot play OGG) can still play it back.
 */
async function voiceNote({ file, storagePath, prefix, mimeType, fileName, size, durationMs }) {
  const ext = fileName.split('.').pop().toLowerCase();
  if (!VOICE_SOURCE_MIMES.includes(mimeType) || !VOICE_SOURCE_EXTS.includes(ext)) {
    throw new HttpError(415, 'Voice notes must be recorded as AAC (.m4a).', 'UNSUPPORTED_MEDIA');
  }
  if (!Number.isFinite(size) || size <= 0 || size > MAX_MEDIA_BYTES) {
    throw new HttpError(413, 'Voice note is empty or too large.', 'MEDIA_TOO_LARGE');
  }
  const [src] = await file.download();
  const ogg = await transcodeToOggOpus(src, { ext });
  const oggPath = `${prefix}voice.ogg`;
  const oggFile = getStorageBucket().file(oggPath);
  await oggFile.save(ogg, { contentType: 'audio/ogg', resumable: false });
  return {
    type: 'audio',
    file: oggFile,
    doc: { storagePath: oggPath, playbackPath: storagePath, mimeType: 'audio/ogg', fileName: 'voice.ogg', size: ogg.length, voice: true, ...durationMs },
  };
}

/**
 * A URL Twilio can fetch. Uses Firebase's download-token URL instead of an IAM-signed URL:
 * Cloud Functions' default service account cannot sign without extra IAM roles.
 */
async function signedUrlFor(file) {
  const [meta] = await file.getMetadata();
  let token = String(meta.metadata?.firebaseStorageDownloadTokens ?? '').split(',')[0];
  if (!token) {
    token = randomUUID();
    await file.setMetadata({ metadata: { firebaseStorageDownloadTokens: token } });
  }
  return `https://firebasestorage.googleapis.com/v0/b/${file.bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${token}`;
}

function leadUpdateForOutbound(type, body, now) {
  return {
    lastMessage: previewFor(type, body), lastMessageType: type, lastMessageAt: now, updatedAt: now,
  };
}

/**
 * kind: 'text' | 'media' | 'template'. Creates the message doc (status
 * `sending`), calls Twilio, records the SID — or `failed` + error. Idempotent
 * on messageId.
 */
export async function sendOutbound({ uid, leadId, messageId, kind, body, media, mediaUrl, replyToMessageId }) {
  assertMessageId(messageId);
  const lead = await loadOwnedLead(uid, leadId);
  const conversationId = lead.id;
  const msgRef = msgsOf(conversationId).doc(messageId);

  const existing = await msgRef.get();
  if (existing.exists) return { id: messageId, duplicate: true, status: existing.data().status };

  let type; let text = ''; let mediaDoc = null; let template = null; let storageFile = null;

  if (kind === 'text') {
    text = assertText(body);
    if (!text) throw new HttpError(400, 'Message is empty.', 'EMPTY');
    type = 'text';
    await assertWindowOpen(conversationId);
  } else if (kind === 'media') {
    const v = await verifyStoredMedia({ uid, conversationId, messageId, media });
    type = v.type; mediaDoc = v.doc; storageFile = v.file;
    text = type === 'audio' || type === 'document' ? '' : assertText(body); // Twilio: no caption on audio/docs
    await assertWindowOpen(conversationId);
  } else if (kind === 'template') {
    const c = assertTwilioConfigured({ needTemplate: true });
    const variable = templateMediaVariable(uid, mediaUrl, c.templateMediaPrefix);
    type = 'template';
    const storagePath = decodeURIComponent(variable.split('?')[0]);
    mediaDoc = { storagePath, mimeType: 'image/jpeg', fileName: storagePath.split('/').pop() };
    template = { contentSid: c.templateContentSid, variables: { 1: variable } };
    text = await fetchTemplateBody(c.templateContentSid);
  } else {
    throw new HttpError(400, 'Unknown message kind.', 'BAD_KIND');
  }

  let replyTo = null;
  if (replyToMessageId) {
    const r = await msgsOf(conversationId).doc(String(replyToMessageId)).get();
    if (r.exists) replyTo = r.id;
  }

  const now = FieldValue.serverTimestamp();
  const doc = {
    id: messageId, conversationId, leadId: lead.id, direction: 'outbound', type, body: text,
    media: mediaDoc, template, twilioSid: null, status: 'sending', senderId: uid,
    createdAt: now, sentAt: null, deliveredAt: null, readAt: null, failedAt: null,
    errorCode: null, errorMessage: null, replyToMessageId: replyTo, deletedAt: null,
  };
  const batch = db().batch();
  batch.create(msgRef, doc);
  batch.update(db().collection(LEADS).doc(lead.id), leadUpdateForOutbound(type, text, now));
  batch.set(db().collection(CONVS).doc(conversationId), { lastOutboundAt: now }, { merge: true });
  await batch.commit();

  await dispatchToTwilio({ conversationId, messageId, lead, doc, storageFile, kind });
  return { id: messageId, duplicate: false };
}

/** Extracts Twilio's `{{1}}` value and checks it points inside the caller's own folder. */
export function templateMediaVariable(uid, mediaUrl, prefix) {
  const url = String(mediaUrl ?? '').trim();
  if (!url.startsWith('https://')) throw new HttpError(400, 'Template image must be an https URL.', 'BAD_TEMPLATE_MEDIA');
  const variable = url.startsWith(prefix) ? url.slice(prefix.length) : null;
  if (!variable) throw new HttpError(400, 'Template image must be a Firebase Storage URL of this project.', 'BAD_TEMPLATE_MEDIA');
  if (!variable.startsWith(`outreach_images%2F${uid}%2F`)) {
    throw new HttpError(403, 'Template image is not in your upload folder.', 'BAD_TEMPLATE_MEDIA');
  }
  return variable;
}

async function dispatchToTwilio({ conversationId, messageId, lead, doc, storageFile, kind }) {
  const c = twilioConfig();
  const params = { To: `whatsapp:${lead.phoneNumber}`, MessagingServiceSid: c.messagingServiceSid };
  if (c.publicBaseUrl) {
    params.StatusCallback = `${c.publicBaseUrl}/twilioStatus?c=${encodeURIComponent(conversationId)}&m=${encodeURIComponent(messageId)}`;
  } else {
    log('PUBLIC_BASE_URL not set: no StatusCallback, status will stay "sending" until refreshed');
  }
  try {
    if (doc.type === 'template') {
      params.ContentSid = doc.template.contentSid;
      params.ContentVariables = JSON.stringify(doc.template.variables);
    } else {
      if (doc.body) params.Body = doc.body;
      if (kind === 'media') params.MediaUrl = await signedUrlFor(storageFile ?? getStorageBucket().file(doc.media.storagePath));
    }
    const r = await createTwilioMessage(params);
    if (!r.ok) {
      await markFailed(conversationId, messageId, r.errorCode, describeTwilioError(r.errorCode, r.errorMessage));
      return;
    }
    // 201 only means "accepted": status stays `sending` until the callback says otherwise.
    await msgsOf(conversationId).doc(messageId).update({ twilioSid: r.sid });
  } catch (err) {
    log('dispatch error', messageId, err.message);
    await markFailed(conversationId, messageId, null, err.message || 'Could not reach Twilio');
  }
}

async function markFailed(conversationId, messageId, errorCode, errorMessage) {
  await msgsOf(conversationId).doc(messageId).update({
    status: 'failed', failedAt: FieldValue.serverTimestamp(), errorCode: errorCode ?? null, errorMessage,
  });
}

/** Re-sends a failed/undelivered outbound message (same doc, new Twilio SID). */
export async function retryOutbound({ uid, leadId, messageId }) {
  const lead = await loadOwnedLead(uid, leadId);
  const ref = msgsOf(lead.id).doc(String(messageId));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpError(404, 'Message not found.', 'NOT_FOUND');
  const m = snap.data();
  if (m.direction !== 'outbound') throw new HttpError(400, 'Only outbound messages can be retried.', 'BAD_REQUEST');
  if (m.status !== 'failed' && m.status !== 'undelivered') throw new HttpError(409, 'Message has not failed.', 'NOT_FAILED');
  let storageFile = null;
  if (m.type === 'template') {
    assertTwilioConfigured({ needTemplate: true });
  } else {
    await assertWindowOpen(lead.id);
    if (m.media) {
      storageFile = getStorageBucket().file(m.media.storagePath);
      const [exists] = await storageFile.exists();
      if (!exists) throw new HttpError(410, 'The uploaded file no longer exists. Send it again.', 'MEDIA_NOT_FOUND');
    }
  }
  await ref.update({
    status: 'sending', failedAt: null, errorCode: null, errorMessage: null, twilioSid: null,
  });
  await dispatchToTwilio({
    conversationId: lead.id, messageId: m.id, lead, doc: m, storageFile, kind: m.type === 'template' ? 'template' : m.media ? 'media' : 'text',
  });
  return { id: m.id };
}

// ---- reactions -------------------------------------------------------------

const EMOJI_RE = /^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|‍|️)+$/u;

/** Returns the emoji to store, or null to remove the reaction. */
export function validateReaction(emoji) {
  if (emoji === null || emoji === undefined || emoji === '') return null;
  const e = String(emoji);
  if (e.length > 16 || !EMOJI_RE.test(e)) throw new HttpError(400, 'Reaction must be a single emoji.', 'BAD_REACTION');
  return e;
}

/**
 * Stores the owner's reaction on a message (`reactions.<uid>`); null removes it.
 * Inbox-only: Twilio's WhatsApp API has no way to send a reaction to the contact.
 */
export async function setReaction({ uid, leadId, messageId, emoji }) {
  const lead = await loadOwnedLead(uid, leadId);
  const e = validateReaction(emoji);
  const ref = msgsOf(lead.id).doc(String(messageId ?? ''));
  const snap = await ref.get();
  if (!snap.exists || snap.data().deletedAt) throw new HttpError(404, 'Message not found.', 'NOT_FOUND');
  await ref.update({ [`reactions.${uid}`]: e === null ? FieldValue.delete() : e });
  return { id: ref.id, reaction: e };
}

// ---- status callbacks ------------------------------------------------------

/** Applies a Twilio status callback (idempotent, order-safe). */
export async function applyStatusCallback({ conversationId, messageId, twilioSid, rawStatus, errorCode }) {
  const incoming = mapTwilioStatus(rawStatus);
  if (!incoming || !conversationId || !messageId) return { applied: false };
  const ref = msgsOf(conversationId).doc(messageId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { applied: false };
    const cur = snap.data();
    const patch = {};
    if (twilioSid && !cur.twilioSid) patch.twilioSid = twilioSid;
    const next = nextStatus(cur.status, incoming);
    if (next) {
      const now = FieldValue.serverTimestamp();
      patch.status = next;
      if (next === 'sent' && !cur.sentAt) patch.sentAt = now;
      if (next === 'delivered') { patch.deliveredAt = now; if (!cur.sentAt) patch.sentAt = now; }
      if (next === 'read') { patch.readAt = now; if (!cur.deliveredAt) patch.deliveredAt = now; if (!cur.sentAt) patch.sentAt = now; }
      if (next === 'failed' || next === 'undelivered') {
        patch.failedAt = now;
        patch.errorCode = errorCode ? Number(errorCode) : null;
        patch.errorMessage = describeTwilioError(errorCode, null);
      }
    }
    if (Object.keys(patch).length) tx.update(ref, patch);
    return { applied: Boolean(next), status: next };
  });
}

/** Optional fallback: pulls one message's status from Twilio. */
export async function refreshMessageStatus({ uid, leadId, messageId }) {
  const lead = await loadOwnedLead(uid, leadId);
  const snap = await msgsOf(lead.id).doc(String(messageId)).get();
  if (!snap.exists || !snap.data().twilioSid) throw new HttpError(404, 'Message has no Twilio SID yet.', 'NOT_FOUND');
  const t = await fetchTwilioMessage(snap.data().twilioSid);
  return applyStatusCallback({
    conversationId: lead.id, messageId: snap.id, twilioSid: t.sid, rawStatus: t.status, errorCode: t.error_code,
  });
}

// ---- inbound ---------------------------------------------------------------

async function resolveOwnerLead(phone) {
  const q = await db().collection(LEADS).where('phoneNumber', '==', phone).limit(25).get();
  if (!q.empty) {
    // Shared sender number: route to the owner who most recently wrote to this person.
    const convs = await Promise.all(q.docs.map((d) => db().collection(CONVS).doc(d.id).get()));
    const scored = q.docs.map((d, i) => ({ d, t: convs[i].data()?.lastOutboundAt?.toMillis?.() ?? 0 }));
    scored.sort((a, b) => b.t - a.t);
    const lead = scored[0].d;
    return { id: lead.id, ownerId: lead.data().ownerId };
  }
  const owner = process.env.OUTREACH_DEFAULT_OWNER_UID?.trim();
  if (!owner) return null;
  const { id } = await ensureLead({ ownerId: owner, name: phone, phoneNumber: phone });
  return { id, ownerId: owner };
}

/**
 * Stores an inbound message (id = Twilio SID, so duplicate webhooks are no-ops)
 * then downloads media into Storage. Returns { stored, duplicate }.
 * `awaitMedia` false = respond to Twilio first, download afterwards.
 */
export async function ingestInbound({ sid, from, body, media = [], createdAt = null }, { awaitMedia = true, bumpUnread = true } = {}) {
  const phone = normalizePhone(from);
  const target = await resolveOwnerLead(phone);
  if (!target) {
    log('inbound from unknown number dropped (set OUTREACH_DEFAULT_OWNER_UID to keep these)', phone);
    return { stored: false };
  }
  const { id: conversationId, ownerId } = target;
  const parts = media.length ? media : [null];
  const batch = db().batch();
  const created = createdAt ? Timestamp.fromDate(createdAt) : FieldValue.serverTimestamp();
  const ids = [];
  let lastType = 'text';
  parts.forEach((m, i) => {
    const id = i === 0 ? sid : `${sid}_${i}`;
    ids.push(id);
    const type = m ? messageTypeForMime(m.contentType) : 'text';
    lastType = type;
    batch.create(msgsOf(conversationId).doc(id), {
      id, conversationId, leadId: conversationId, direction: 'inbound', type, body: i === 0 ? (body ?? '') : '',
      media: m ? { storagePath: null, mimeType: baseMime(m.contentType), fileName: `media_${i}.${extForMime(m.contentType)}`, size: null } : null,
      twilioSid: sid, status: 'delivered', senderId: `lead:${conversationId}`, createdAt: created,
      sentAt: created, deliveredAt: created, readAt: null, failedAt: null, errorCode: null, errorMessage: null,
      replyToMessageId: null, deletedAt: null,
    });
  });
  const lastBody = parts.length === 1 ? (body ?? '') : '';
  batch.update(db().collection(LEADS).doc(conversationId), {
    lastMessage: previewFor(lastType, lastBody), lastMessageType: lastType, lastMessageAt: created,
    updatedAt: FieldValue.serverTimestamp(),
    ...(bumpUnread ? { unreadCount: FieldValue.increment(parts.length) } : {}),
  });
  if (bumpUnread) batch.set(db().collection(CONVS).doc(conversationId), { lastInboundAt: created }, { merge: true });
  try {
    await batch.commit();
  } catch (err) {
    if (err.code === 6 || /ALREADY_EXISTS/.test(String(err.message))) return { stored: false, duplicate: true };
    throw err;
  }
  const download = Promise.all(media.map((m, i) => downloadInboundMedia({ ownerId, conversationId, messageId: ids[i], media: m })));
  if (awaitMedia) await download; else download.catch((e) => log('media download error', e.message));
  return { stored: true, duplicate: false, download };
}

async function downloadInboundMedia({ ownerId, conversationId, messageId, media }) {
  const ref = msgsOf(conversationId).doc(messageId);
  try {
    const c = twilioConfig();
    const res = await fetch(media.url, { headers: { Authorization: basicAuth(c) }, redirect: 'follow' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const len = Number(res.headers.get('content-length') ?? 0);
    if (len > MAX_MEDIA_BYTES * 2) throw new Error('media too large');
    const buf = Buffer.from(await res.arrayBuffer());
    const mime = baseMime(media.contentType);
    const fileName = `media_${messageId.includes('_') ? messageId.split('_').pop() : 0}.${extForMime(mime)}`;
    const storagePath = `outreach_media/${ownerId}/${conversationId}/${messageId}/${fileName}`;
    await getStorageBucket().file(storagePath).save(buf, { contentType: mime, resumable: false });
    await ref.update({ 'media.storagePath': storagePath, 'media.size': buf.length, 'media.fileName': fileName });
  } catch (err) {
    log('inbound media failed', messageId, err.message);
    await ref.update({ 'media.error': err.message || 'download failed' }).catch(() => {});
  }
}

// ---- Twilio history (optional, user-triggered) -----------------------------

/** Adds a lead for every WhatsApp number in the last 200 account messages. */
export async function importLeadsFromTwilio(uid) {
  const msgs = await listTwilioMessages({ PageSize: '200' });
  const numbers = new Set();
  for (const m of msgs) {
    const raw = m.direction === 'inbound' ? m.from : m.to;
    if (String(raw).startsWith('whatsapp:')) numbers.add(normalizePhone(raw));
  }
  let created = 0;
  for (const phone of numbers) {
    if (!isValidE164(phone)) continue;
    const r = await ensureLead({ ownerId: uid, name: phone, phoneNumber: phone });
    if (r.created) created++;
  }
  return { found: numbers.size, created };
}

/** Copies Twilio's stored history for one lead into Firestore (existing docs untouched). */
export async function backfillLead({ uid, leadId }) {
  const lead = await loadOwnedLead(uid, leadId);
  const wa = `whatsapp:${lead.phoneNumber}`;
  const [inb, outb] = await Promise.all([
    listTwilioMessages({ From: wa, PageSize: '50' }),
    listTwilioMessages({ To: wa, PageSize: '50' }),
  ]);
  let added = 0;
  for (const m of [...inb, ...outb].sort((a, b) => new Date(a.date_created) - new Date(b.date_created))) {
    const when = new Date(m.date_sent ?? m.date_created);
    const media = Number(m.num_media) > 0 ? await listTwilioMedia(m.sid) : [];
    if (!m.body && media.length === 0) continue; // template shells: cannot be reconstructed from Twilio
    if (m.direction === 'inbound') {
      const r = await ingestInbound({ sid: m.sid, from: m.from, body: m.body, media, createdAt: when }, { bumpUnread: false });
      if (r.stored) added++;
    } else {
      const ref = msgsOf(lead.id).doc(m.sid);
      if ((await ref.get()).exists) continue;
      const first = media[0] ?? null;
      const type = first ? messageTypeForMime(first.contentType) : 'text';
      const created = Timestamp.fromDate(when);
      const status = mapTwilioStatus(m.status) ?? 'sent';
      await ref.set({
        id: m.sid, conversationId: lead.id, leadId: lead.id, direction: 'outbound', type, body: m.body ?? '',
        media: first ? { storagePath: null, mimeType: baseMime(first.contentType), fileName: `media_0.${extForMime(first.contentType)}`, size: null } : null,
        twilioSid: m.sid, status, senderId: uid, createdAt: created, sentAt: created,
        deliveredAt: status === 'delivered' || status === 'read' ? created : null, readAt: status === 'read' ? created : null,
        failedAt: status === 'failed' || status === 'undelivered' ? created : null,
        errorCode: m.error_code ?? null, errorMessage: m.error_code ? describeTwilioError(m.error_code, null) : null,
        replyToMessageId: null, deletedAt: null,
      });
      if (first) await downloadInboundMedia({ ownerId: uid, conversationId: lead.id, messageId: m.sid, media: first });
      added++;
    }
  }
  return { added };
}
