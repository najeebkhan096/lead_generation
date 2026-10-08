/**
 * Firebase Cloud Functions for the WhatsApp (Twilio) chat. No separate server:
 *
 *   outreachApi      callable, called by the app (Firebase Auth + `users/{uid}.approved`)
 *   twilioIncoming   HTTPS webhook  — Twilio posts inbound WhatsApp messages here
 *   twilioStatus     HTTPS webhook  — Twilio posts delivery / read / failed updates here
 *
 * Twilio credentials come from functions/.env (loaded into process.env at runtime).
 */
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { urlencoded } from 'express';
import { getFirestore } from './firebase.js';
import {
  applyStatusCallback, backfillLead, ensureLead, importLeadsFromTwilio, ingestInbound, refreshMessageStatus,
  retryOutbound, sendOutbound, setReaction,
} from './twilioChat/messageService.js';
import { twilioConfig } from './twilioChat/twilioClient.js';
import { isValidTwilioSignature } from './twilioChat/signature.js';
import { HttpError } from './twilioChat/validation.js';

const REGION = 'us-central1';

// Where Twilio reaches the webhooks: https://<region>-<project>.cloudfunctions.net/<name>.
// Override with PUBLIC_BASE_URL in functions/.env if you use a custom domain.
if (!process.env.PUBLIC_BASE_URL && process.env.GCLOUD_PROJECT) {
  process.env.PUBLIC_BASE_URL = `https://${REGION}-${process.env.GCLOUD_PROJECT}.cloudfunctions.net`;
}

// ---- callable ---------------------------------------------------------------

function toHttpsError(err) {
  if (err instanceof HttpsError) return err;
  if (err instanceof HttpError) {
    const s = err.status;
    const code = s === 401 ? 'unauthenticated' : s === 403 ? 'permission-denied' : s === 404 || s === 410 ? 'not-found'
      : s === 409 ? 'failed-precondition' : s === 429 ? 'resource-exhausted' : s === 503 ? 'unavailable'
      : s >= 400 && s < 500 ? 'invalid-argument' : 'internal';
    return new HttpsError(code, err.message, { code: err.code, status: s });
  }
  console.error('[outreachApi] unexpected', err);
  return new HttpsError('internal', 'Something went wrong on the server.', { code: 'INTERNAL' });
}

async function requireApproved(uid) {
  const user = await getFirestore().collection('users').doc(uid).get();
  if (!user.exists || user.data().approved !== true) {
    throw new HttpsError('permission-denied', 'Account not approved', { code: 'FORBIDDEN' });
  }
}

const ACTIONS = {
  text: (uid, b) => sendOutbound({ uid, kind: 'text', leadId: b.leadId, messageId: b.messageId, body: b.body, replyToMessageId: b.replyToMessageId }),
  media: (uid, b) => sendOutbound({ uid, kind: 'media', leadId: b.leadId, messageId: b.messageId, body: b.caption, media: b.media, replyToMessageId: b.replyToMessageId }),
  template: (uid, b) => sendOutbound({ uid, kind: 'template', leadId: b.leadId, messageId: b.messageId, mediaUrl: b.mediaUrl }),
  retry: (uid, b) => retryOutbound({ uid, leadId: b.leadId, messageId: b.messageId }),
  refresh: (uid, b) => refreshMessageStatus({ uid, leadId: b.leadId, messageId: b.messageId }),
  react: (uid, b) => setReaction({ uid, leadId: b.leadId, messageId: b.messageId, emoji: b.emoji }),
  ensureLead: (uid, b) => ensureLead({ ownerId: uid, name: b.name, businessName: b.businessName, phoneNumber: b.phoneNumber, details: b.details }),
  importTwilio: (uid) => importLeadsFromTwilio(uid),
  backfill: (uid, b) => backfillLead({ uid, leadId: b.leadId }),
};

/** Runs one action for an authenticated, approved user. Exported for tests. */
export async function runAction(uid, action, data) {
  const fn = ACTIONS[action];
  if (!fn) throw new HttpsError('invalid-argument', 'Unknown action.', { code: 'BAD_ACTION' });
  try {
    await requireApproved(uid);
    return await fn(uid, data ?? {});
  } catch (err) {
    throw toHttpsError(err);
  }
}

export const outreachApi = onCall(
  { region: REGION, memory: '1GiB', timeoutSeconds: 120, maxInstances: 10 },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'You are signed out.', { code: 'UNAUTHENTICATED' });
    const { action, ...data } = request.data ?? {};
    return runAction(request.auth.uid, String(action ?? ''), data);
  },
);

// ---- Twilio webhooks (authenticated by X-Twilio-Signature) ----------------------

const parseForm = urlencoded({ extended: false });

/** Reads the form body and checks the signature against the exact URL Twilio called. */
function verified(name, req, res) {
  return new Promise((resolve) => {
    const c = twilioConfig();
    if (!c.authToken || !c.publicBaseUrl) {
      res.status(503).send('Webhook not configured');
      return resolve(null);
    }
    parseForm(req, res, () => {
      const search = req.url.includes('?') ? req.url.slice(req.url.indexOf('?')) : '';
      const url = `${c.publicBaseUrl}/${name}${search}`;
      const params = req.body ?? {};
      if (!isValidTwilioSignature(c.authToken, req.get('X-Twilio-Signature'), url, params)) {
        res.status(403).send('Invalid signature');
        return resolve(null);
      }
      resolve(params);
    });
  });
}

const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response/>';

export const twilioIncoming = onRequest({ region: REGION, memory: '512MiB', timeoutSeconds: 60, invoker: 'public' }, async (req, res) => {
  if (req.method !== 'POST') return void res.status(405).send('POST only');
  const p = await verified('twilioIncoming', req, res);
  if (!p) return;
  try {
    const media = [];
    for (let i = 0; i < Number(p.NumMedia || 0); i++) {
      media.push({ url: p[`MediaUrl${i}`], contentType: p[`MediaContentType${i}`] });
    }
    // Cloud Functions throttles CPU once the response is sent, so the media copy is awaited.
    await ingestInbound({ sid: p.MessageSid, from: p.From, body: p.Body, media }, { awaitMedia: true });
    res.type('text/xml').send(EMPTY_TWIML);
  } catch (err) {
    console.error('[twilioIncoming]', err);
    res.status(500).send('error'); // Twilio retries; the message id (Twilio SID) makes that idempotent
  }
});

export const twilioStatus = onRequest({ region: REGION, timeoutSeconds: 30, invoker: 'public' }, async (req, res) => {
  if (req.method !== 'POST') return void res.status(405).send('POST only');
  const p = await verified('twilioStatus', req, res);
  if (!p) return;
  try {
    await applyStatusCallback({
      conversationId: req.query.c, messageId: req.query.m, twilioSid: p.MessageSid,
      rawStatus: p.MessageStatus ?? p.SmsStatus, errorCode: p.ErrorCode,
    });
    res.sendStatus(204);
  } catch (err) {
    console.error('[twilioStatus]', err);
    res.status(500).send('error');
  }
});
