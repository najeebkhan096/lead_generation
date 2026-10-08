import {
  applyStatusCallback, backfillLead, ensureLead, importLeadsFromTwilio, ingestInbound, refreshMessageStatus,
  retryOutbound, sendOutbound, setReaction,
} from '../services/twilioChat/messageService.js';
import { twilioConfig } from '../services/twilioChat/twilioClient.js';
import { isValidTwilioSignature } from '../services/twilioChat/signature.js';
import { HttpError } from '../services/twilioChat/validation.js';

export const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Error handler for this feature: JSON `{error, code}` with the right status. */
export function chatErrorHandler(err, _req, res, next) {
  if (err instanceof HttpError || err.status) {
    return res.status(err.status || 500).json({ error: err.message, code: err.code });
  }
  return next(err);
}

const body = (req) => req.body ?? {};

export const postText = wrap(async (req, res) => {
  const b = body(req);
  res.status(202).json(await sendOutbound({ uid: req.uid, kind: 'text', leadId: b.leadId, messageId: b.messageId, body: b.body, replyToMessageId: b.replyToMessageId }));
});

export const postMedia = wrap(async (req, res) => {
  const b = body(req);
  res.status(202).json(await sendOutbound({ uid: req.uid, kind: 'media', leadId: b.leadId, messageId: b.messageId, body: b.caption, media: b.media, replyToMessageId: b.replyToMessageId }));
});

export const postTemplate = wrap(async (req, res) => {
  const b = body(req);
  res.status(202).json(await sendOutbound({ uid: req.uid, kind: 'template', leadId: b.leadId, messageId: b.messageId, mediaUrl: b.mediaUrl }));
});

export const postRetry = wrap(async (req, res) => {
  const b = body(req);
  res.status(202).json(await retryOutbound({ uid: req.uid, leadId: b.leadId, messageId: b.messageId }));
});

export const postReaction = wrap(async (req, res) => {
  const b = body(req);
  res.json(await setReaction({ uid: req.uid, leadId: b.leadId, messageId: b.messageId, emoji: b.emoji }));
});

export const postRefresh = wrap(async (req, res) => {
  const b = body(req);
  res.json(await refreshMessageStatus({ uid: req.uid, leadId: b.leadId, messageId: b.messageId }));
});

export const postImportLeads = wrap(async (req, res) => {
  res.json(await importLeadsFromTwilio(req.uid));
});

export const postBackfill = wrap(async (req, res) => {
  res.json(await backfillLead({ uid: req.uid, leadId: req.params.leadId }));
});

/** Creates (idempotently) a lead + conversation for the caller. */
export const postEnsureLead = wrap(async (req, res) => {
  const b = body(req);
  res.json(await ensureLead({ ownerId: req.uid, name: b.name, businessName: b.businessName, phoneNumber: b.phoneNumber }));
});

// ---- Twilio webhooks (no Firebase auth: authenticated by X-Twilio-Signature) -------------

function verifyTwilio(req) {
  const c = twilioConfig();
  if (!c.authToken || !c.publicBaseUrl) {
    throw new HttpError(503, 'Webhook not configured (TWILIO_AUTH_TOKEN / PUBLIC_BASE_URL).', 'NOT_CONFIGURED');
  }
  const url = `${c.publicBaseUrl}${req.originalUrl}`;
  if (!isValidTwilioSignature(c.authToken, req.get('X-Twilio-Signature'), url, req.body ?? {})) {
    throw new HttpError(403, 'Invalid Twilio signature.', 'BAD_SIGNATURE');
  }
}

const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response/>';

export const webhookIncoming = wrap(async (req, res) => {
  verifyTwilio(req);
  const p = req.body;
  const media = [];
  for (let i = 0; i < Number(p.NumMedia || 0); i++) {
    media.push({ url: p[`MediaUrl${i}`], contentType: p[`MediaContentType${i}`] });
  }
  // Persist the message first, answer Twilio, then download media in the background.
  await ingestInbound({ sid: p.MessageSid, from: p.From, body: p.Body, media }, { awaitMedia: false });
  res.type('text/xml').send(EMPTY_TWIML);
});

export const webhookStatus = wrap(async (req, res) => {
  verifyTwilio(req);
  const p = req.body;
  await applyStatusCallback({
    conversationId: req.query.c, messageId: req.query.m, twilioSid: p.MessageSid,
    rawStatus: p.MessageStatus ?? p.SmsStatus, errorCode: p.ErrorCode,
  });
  res.sendStatus(204);
});
