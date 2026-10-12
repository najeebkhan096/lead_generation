/**
 * Thin Twilio REST client. The ONLY place the Auth Token is read — it comes
 * from environment variables and never leaves the backend.
 */
import { HttpError } from './validation.js';
import { TWILIO_DEFAULTS as D } from './twilioDefaults.js';

export function twilioConfig() {
  const c = {
    accountSid: process.env.TWILIO_ACCOUNT_SID?.trim() || D.accountSid,
    authToken: process.env.TWILIO_AUTH_TOKEN?.trim() || D.authToken,
    messagingServiceSid: process.env.TWILIO_MESSAGING_SERVICE_SID?.trim() || D.messagingServiceSid,
    templateContentSid: process.env.TWILIO_TEMPLATE_CONTENT_SID?.trim() || D.templateContentSid,
    // The template's media URL is `<prefix>{{1}}`; variable 1 is only the part after it.
    templateMediaPrefix:
      process.env.TWILIO_TEMPLATE_MEDIA_PREFIX?.trim() ||
      'https://firebasestorage.googleapis.com/v0/b/whatsapplead-a8d9a.firebasestorage.app/o/',
    publicBaseUrl: process.env.PUBLIC_BASE_URL?.trim().replace(/\/+$/, ''),
  };
  return c;
}

export function assertTwilioConfigured({ needTemplate = false } = {}) {
  const c = twilioConfig();
  if (!c.accountSid || !c.authToken || !c.messagingServiceSid) {
    throw new HttpError(503, 'Twilio is not configured on the server.', 'TWILIO_NOT_CONFIGURED');
  }
  if (needTemplate && !c.templateContentSid) {
    throw new HttpError(503, 'Twilio template is not configured on the server.', 'TWILIO_NOT_CONFIGURED');
  }
  return c;
}

export function basicAuth(c = twilioConfig()) {
  return `Basic ${Buffer.from(`${c.accountSid}:${c.authToken}`).toString('base64')}`;
}

const BASE = 'https://api.twilio.com/2010-04-01/Accounts';

/** POST a message. Returns { ok, sid, status, errorCode, errorMessage }. */
export async function createTwilioMessage(params) {
  const c = assertTwilioConfigured();
  const res = await fetch(`${BASE}/${c.accountSid}/Messages.json`, {
    method: 'POST',
    headers: { Authorization: basicAuth(c), 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
  const json = await res.json().catch(() => ({}));
  if (res.status === 200 || res.status === 201) {
    return { ok: true, sid: json.sid, status: json.status };
  }
  return { ok: false, httpStatus: res.status, errorCode: json.code, errorMessage: json.message ?? `HTTP ${res.status}` };
}

export async function fetchTwilioMessage(sid) {
  const c = assertTwilioConfigured();
  const res = await fetch(`${BASE}/${c.accountSid}/Messages/${sid}.json`, { headers: { Authorization: basicAuth(c) } });
  if (!res.ok) throw new HttpError(502, `Twilio lookup failed (HTTP ${res.status}).`, 'TWILIO_ERROR');
  return res.json();
}

export async function listTwilioMessages(query) {
  const c = assertTwilioConfigured();
  const qs = new URLSearchParams(query);
  const res = await fetch(`${BASE}/${c.accountSid}/Messages.json?${qs}`, { headers: { Authorization: basicAuth(c) } });
  if (!res.ok) throw new HttpError(502, `Twilio list failed (HTTP ${res.status}).`, 'TWILIO_ERROR');
  return (await res.json()).messages ?? [];
}

export async function listTwilioMedia(messageSid) {
  const c = assertTwilioConfigured();
  const res = await fetch(`${BASE}/${c.accountSid}/Messages/${messageSid}/Media.json`, { headers: { Authorization: basicAuth(c) } });
  if (!res.ok) return [];
  const json = await res.json();
  return (json.media_list ?? []).map((m) => ({
    url: `https://api.twilio.com${m.uri.replace(/\.json$/, '')}`,
    contentType: m.content_type,
  }));
}
