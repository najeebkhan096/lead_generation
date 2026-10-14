/**
 * Chat with a Twilio test lead from the web admin.
 *
 * Reuses the mobile app's message pipeline (../twilio-chat/messageService.js),
 * so a message sent here is the same Firestore document, with the same
 * 24-hour-window / SMS / template rules, as one sent from the phone.
 *
 * This server has no public URL for Twilio's webhooks, so replies and
 * delivery receipts are pulled from Twilio's API by `sync` instead.
 */
import { randomUUID } from 'node:crypto';
import { getFirestore, getStorageBucket } from '../../firebase/admin.js';
import {
  applyStatusCallback, ingestInbound, retryOutbound, sendOutbound,
} from '../twilio-chat/messageService.js';
import { fetchTwilioMessage, listTwilioMedia, listTwilioMessages } from '../twilio-chat/twilioClient.js';
import { HttpError, WINDOW_MS } from '../twilio-chat/validation.js';

const LEADS = 'outreachLeads';
const CONVS = 'outreachConversations';
const MESSAGE_LIMIT = 200;
const MAX_STATUS_REFRESH = 10;
const TEXT_KINDS = ['text', 'sms'];
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // WhatsApp template header images: JPEG/PNG up to 5 MB.

const IMAGE_TYPES = {
  'image/jpeg': { ext: 'jpg', magic: [0xff, 0xd8, 0xff] },
  'image/png': { ext: 'png', magic: [0x89, 0x50, 0x4e, 0x47] },
};

const millis = (ts) => (typeof ts?.toMillis === 'function' ? ts.toMillis() : null);

export function messageJson(id, d) {
  return {
    id,
    direction: d.direction ?? 'outbound',
    type: d.type ?? 'text',
    channel: d.channel ?? 'whatsapp',
    body: d.body ?? '',
    status: d.status ?? 'sending',
    errorCode: d.errorCode ?? null,
    errorMessage: d.errorMessage ?? null,
    createdAt: millis(d.createdAt),
    mediaName: d.media?.fileName ?? null,
  };
}

/** Decodes `data` (plain or data-URL base64) and checks it really is the declared image type. */
export function decodeImage(data, mimeType) {
  const type = IMAGE_TYPES[mimeType];
  if (!type) throw new HttpError(415, 'The image must be a JPEG or PNG.', 'UNSUPPORTED_MEDIA');
  const raw = String(data ?? '').replace(/^data:[^,]*,/, '');
  const bytes = Buffer.from(raw, 'base64');
  if (bytes.length === 0) throw new HttpError(400, 'The image is empty.', 'EMPTY');
  if (bytes.length > MAX_IMAGE_BYTES) throw new HttpError(413, 'The image is larger than 5 MB.', 'MEDIA_TOO_LARGE');
  if (!type.magic.every((b, i) => bytes[i] === b)) {
    throw new HttpError(415, 'The file is not a valid JPEG or PNG image.', 'UNSUPPORTED_MEDIA');
  }
  return { bytes, ext: type.ext };
}

const newMessageId = () => randomUUID().replace(/-/g, '');

export function chatService(overrides = {}) {
  const d = {
    db: getFirestore,
    bucket: getStorageBucket,
    sendOutbound,
    retryOutbound,
    ingestInbound,
    applyStatusCallback,
    fetchTwilioMessage,
    listTwilioMessages,
    listTwilioMedia,
    ...overrides,
  };
  const msgsOf = (id) => d.db().collection(CONVS).doc(id).collection('messages');

  /**
   * Test leads, and leads that replied to an outreach email on WhatsApp
   * (`repliedViaLink`), are reachable from the web admin; nothing else is.
   */
  async function loadTestLead(leadId) {
    const id = String(leadId ?? '');
    const snap = id ? await d.db().collection(LEADS).doc(id).get() : null;
    if (!snap?.exists) throw new HttpError(404, 'Lead not found.', 'LEAD_NOT_FOUND');
    const lead = snap.data();
    if (lead.isTest !== true && lead.repliedViaLink !== true) {
      throw new HttpError(403, 'Only test leads and WhatsApp replies can be used here.', 'NOT_A_TEST_LEAD');
    }
    return { id, ...lead };
  }

  async function recentMessages(id) {
    const snap = await msgsOf(id).orderBy('createdAt', 'desc').limit(MESSAGE_LIMIT).get();
    return snap.docs
      .map((doc) => ({ id: doc.id, ...doc.data() }))
      .filter((m) => !m.deletedAt)
      .reverse();
  }

  async function readMessage(leadId, messageId) {
    const snap = await msgsOf(leadId).doc(messageId).get();
    if (!snap.exists) throw new HttpError(404, 'Message not found.', 'NOT_FOUND');
    return messageJson(snap.id, snap.data());
  }

  return {
    /** Messages (oldest first) and when the WhatsApp free-text window closes (null = closed). */
    async getChat(leadId) {
      const lead = await loadTestLead(leadId);
      // Opening the conversation reads it.
      if (Number(lead.unreadCount) > 0) {
        await d.db().collection(LEADS).doc(lead.id).update({ unreadCount: 0 });
      }
      const [conv, messages] = await Promise.all([
        d.db().collection(CONVS).doc(lead.id).get(),
        recentMessages(lead.id),
      ]);
      const lastInbound = millis(conv.data()?.lastInboundAt);
      const closesAt = lastInbound === null ? null : lastInbound + WINDOW_MS;
      return {
        messages: messages.map((m) => messageJson(m.id, m)),
        windowClosesAt: closesAt !== null && closesAt > Date.now() ? closesAt : null,
      };
    },

    /** kind `text` = WhatsApp free text (needs an open window), `sms` = plain SMS. */
    async sendText(leadId, { kind, body }) {
      if (!TEXT_KINDS.includes(kind)) throw new HttpError(400, 'kind must be "text" or "sms".', 'BAD_KIND');
      const lead = await loadTestLead(leadId);
      const messageId = newMessageId();
      await d.sendOutbound({ uid: lead.ownerId, leadId: lead.id, messageId, kind, body });
      return readMessage(lead.id, messageId);
    },

    /** The approved outreach template with an uploaded header image. */
    async sendTemplate(leadId, { imageBase64, mimeType, channel }) {
      const lead = await loadTestLead(leadId);
      const { bytes, ext } = decodeImage(imageBase64, mimeType);
      const token = randomUUID();
      const path = `outreach_images/${lead.ownerId}/${Date.now()}_${randomUUID().slice(0, 8)}.${ext}`;
      const file = d.bucket().file(path);
      await file.save(bytes, {
        contentType: mimeType,
        resumable: false,
        metadata: { metadata: { firebaseStorageDownloadTokens: token } },
      });
      const mediaUrl = `https://firebasestorage.googleapis.com/v0/b/${file.bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
      const messageId = newMessageId();
      await d.sendOutbound({
        uid: lead.ownerId, leadId: lead.id, messageId, kind: 'template', mediaUrl,
        channel: ['whatsapp', 'sms'].includes(channel) ? channel : 'auto',
      });
      return readMessage(lead.id, messageId);
    },

    async retry(leadId, messageId) {
      const lead = await loadTestLead(leadId);
      await d.retryOutbound({ uid: lead.ownerId, leadId: lead.id, messageId });
      return readMessage(lead.id, String(messageId));
    },

    /**
     * Pulls delivery receipts and replies from Twilio (no webhooks reach this
     * server). Safe to call repeatedly: replies are keyed by Twilio SID.
     */
    async sync(leadId) {
      const lead = await loadTestLead(leadId);
      const messages = await recentMessages(lead.id);
      let statusUpdates = 0;
      let ingested = 0;

      // WhatsApp keeps reporting after "delivered" (read receipts), SMS does not.
      const open = messages
        .filter((m) => m.direction === 'outbound' && m.twilioSid
          && (['sending', 'sent'].includes(m.status) || (m.status === 'delivered' && m.channel !== 'sms')))
        .slice(-MAX_STATUS_REFRESH);
      for (const m of open) {
        try {
          const t = await d.fetchTwilioMessage(m.twilioSid);
          const r = await d.applyStatusCallback({
            conversationId: lead.id, messageId: m.id, twilioSid: t.sid, rawStatus: t.status, errorCode: t.error_code,
          });
          if (r.applied) statusUpdates += 1;
        } catch {
          // Keep going: one unreachable receipt must not hide the replies.
        }
      }

      const known = new Set(messages.map((m) => m.id));
      const [viaWhatsApp, viaSms] = await Promise.all([
        d.listTwilioMessages({ From: `whatsapp:${lead.phoneNumber}`, PageSize: '20' }),
        d.listTwilioMessages({ From: lead.phoneNumber, PageSize: '20' }),
      ]);
      const unseen = new Map();
      for (const m of [...viaWhatsApp, ...viaSms]) {
        if (m.direction === 'inbound' && !known.has(m.sid)) unseen.set(m.sid, m);
      }
      const inbound = [...unseen.values()]
        .sort((a, b) => new Date(a.date_sent ?? a.date_created) - new Date(b.date_sent ?? b.date_created));
      for (const m of inbound) {
        const media = Number(m.num_media) > 0 ? await d.listTwilioMedia(m.sid) : [];
        if (!m.body && media.length === 0) continue;
        const r = await d.ingestInbound({
          sid: m.sid, from: m.from, body: m.body, media, createdAt: new Date(m.date_sent ?? m.date_created),
        });
        if (r.stored) ingested += 1;
      }
      return { statusUpdates, ingested };
    },
  };
}
