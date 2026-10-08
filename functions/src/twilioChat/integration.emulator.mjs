// Backend logic against the Firestore + Storage emulators with Twilio mocked.
// Run: npm run test:twilio:emulator   (needs Java 21+ on PATH for the emulators)
import test from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

process.env.TWILIO_ACCOUNT_SID = 'ACtest';
process.env.TWILIO_AUTH_TOKEN = 'tok';
process.env.TWILIO_MESSAGING_SERVICE_SID = 'MGtest';
process.env.TWILIO_TEMPLATE_CONTENT_SID = 'HXtest';
process.env.PUBLIC_BASE_URL = 'https://api.example.com';
initializeApp({ projectId: 'demo-chat', storageBucket: 'demo-chat.appspot.com' });
const db = getFirestore();

const svc = await import('./messageService.js');

const realFetch = globalThis.fetch;
// ---- fake Twilio ----------------------------------------------------------
const twilioCalls = [];
let nextResponse = null;
let sidCounter = 0;
globalThis.fetch = async (url, init = {}) => {
  const u = String(url);
  if (u.startsWith('https://api.twilio.com') && init.method === 'POST') {
    const params = Object.fromEntries(new URLSearchParams(init.body));
    twilioCalls.push(params);
    if (nextResponse) { const r = nextResponse; nextResponse = null; return r; }
    return new Response(JSON.stringify({ sid: `SM${++sidCounter}`, status: 'queued' }), { status: 201 });
  }
  if (u.startsWith('https://media.example')) {
    return new Response(Buffer.from('JPEGDATA'), { status: 200, headers: { 'content-type': 'image/jpeg' } });
  }
  throw new Error(`unexpected fetch ${u}`);
};

const OWNER = 'ownerA';
const PHONE = '+971501234567';
const msgs = (lead) => db.collection(`outreachConversations/${lead}/messages`);
const get = async (lead, id) => (await msgs(lead).doc(id).get()).data();
let LEAD;

test('ensureLead is idempotent and creates lead + conversation', async () => {
  const a = await svc.ensureLead({ ownerId: OWNER, name: 'Bob', businessName: 'B Co', phoneNumber: '+971 50 123 4567' });
  const b = await svc.ensureLead({ ownerId: OWNER, name: 'Other', phoneNumber: PHONE });
  LEAD = a.id;
  assert.equal(a.id, `${OWNER}_971501234567`);
  assert.equal(a.created, true);
  assert.equal(b.created, false);
  assert.equal((await db.collection('outreachConversations').doc(LEAD).get()).data().ownerId, OWNER);
  await assert.rejects(svc.ensureLead({ ownerId: OWNER, name: 'x', phoneNumber: '12345' }), (e) => e.code === 'INVALID_PHONE');
});

test('text is refused while the 24h window is closed', async () => {
  await assert.rejects(
    svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgText0001', kind: 'text', body: 'hi' }),
    (e) => e.code === 'WINDOW_CLOSED' && e.status === 409,
  );
  assert.equal(twilioCalls.length, 0);
});

test('template send: strips the media prefix, stores the message, status stays "sending"', async () => {
  const prefix = 'https://firebasestorage.googleapis.com/v0/b/whatsapplead-a8d9a.firebasestorage.app/o/';
  const variable = `outreach_images%2F${OWNER}%2F1.jpg?alt=media&token=abc`;
  await svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgTmpl0001', kind: 'template', mediaUrl: prefix + variable });
  const call = twilioCalls.at(-1);
  assert.equal(call.ContentSid, 'HXtest');
  assert.equal(call.MessagingServiceSid, 'MGtest');
  assert.equal(call.To, `whatsapp:${PHONE}`);
  assert.deepEqual(JSON.parse(call.ContentVariables), { 1: variable }); // NOT the full URL (21620)
  assert.match(call.StatusCallback, /twilioStatus\?c=.*&m=msgTmpl0001$/);
  const m = await get(LEAD, 'msgTmpl0001');
  assert.equal(m.type, 'template');
  assert.equal(m.status, 'sending');
  assert.equal(m.twilioSid, 'SM1');
  assert.equal(m.template.contentSid, 'HXtest');
  const lead = (await db.collection('outreachLeads').doc(LEAD).get()).data();
  assert.equal(lead.lastMessageType, 'template');
  // another user's folder is refused
  await assert.rejects(
    svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgTmpl0002', kind: 'template', mediaUrl: prefix + 'outreach_images%2FsomeoneElse%2F1.jpg?alt=media' }),
    (e) => e.status === 403,
  );
});

test('only the owner can send to a lead', async () => {
  await assert.rejects(svc.sendOutbound({ uid: 'mallory', leadId: LEAD, messageId: 'msgEvil0001', kind: 'template', mediaUrl: 'x' }), (e) => e.status === 403);
});

test('duplicate messageId does not send twice', async () => {
  const before = twilioCalls.length;
  const r = await svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgTmpl0001', kind: 'template', mediaUrl: 'https://x' });
  assert.equal(r.duplicate, true);
  assert.equal(twilioCalls.length, before);
});

test('status callbacks: ordered, duplicate-safe, out-of-order-safe', async () => {
  const cb = (rawStatus, extra = {}) => svc.applyStatusCallback({ conversationId: LEAD, messageId: 'msgTmpl0001', twilioSid: 'SM1', rawStatus, ...extra });
  assert.equal((await cb('queued')).applied, false);
  assert.equal((await cb('sent')).status, 'sent');
  assert.equal((await cb('sent')).applied, false);            // duplicate
  assert.equal((await cb('read')).status, 'read');
  assert.equal((await cb('delivered')).applied, false);        // late, out of order
  assert.equal((await cb('failed', { errorCode: '63016' })).applied, false); // cannot fail after read
  const m = await get(LEAD, 'msgTmpl0001');
  assert.equal(m.status, 'read');
  assert.ok(m.sentAt && m.deliveredAt && m.readAt);
});

test('Twilio rejection => failed with friendly error, then retry works', async () => {
  const prefix = 'https://firebasestorage.googleapis.com/v0/b/whatsapplead-a8d9a.firebasestorage.app/o/';
  nextResponse = new Response(JSON.stringify({ code: 21620, message: 'bad media' }), { status: 400 });
  await svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgFail0001', kind: 'template', mediaUrl: `${prefix}outreach_images%2F${OWNER}%2F2.jpg?alt=media&token=t` });
  let m = await get(LEAD, 'msgFail0001');
  assert.equal(m.status, 'failed');
  assert.equal(m.errorCode, 21620);
  assert.match(m.errorMessage, /media URL/);
  await svc.retryOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgFail0001' });
  m = await get(LEAD, 'msgFail0001');
  assert.equal(m.status, 'sending');
  assert.ok(m.twilioSid);
  assert.equal(m.errorCode, null);
  await assert.rejects(svc.retryOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgFail0001' }), (e) => e.code === 'NOT_FAILED');
});

test('failed status callback records error code', async () => {
  await svc.applyStatusCallback({ conversationId: LEAD, messageId: 'msgFail0001', twilioSid: 'x', rawStatus: 'undelivered', errorCode: '63024' });
  const m = await get(LEAD, 'msgFail0001');
  assert.equal(m.status, 'undelivered');
  assert.equal(m.errorCode, 63024);
});

test('inbound text: stored once (duplicate webhook ignored), unread + window updated', async () => {
  const p = { sid: 'SMin0001', from: `whatsapp:${PHONE}`, body: 'hello there', media: [] };
  assert.equal((await svc.ingestInbound(p)).stored, true);
  assert.equal((await svc.ingestInbound(p)).duplicate, true);
  const lead = (await db.collection('outreachLeads').doc(LEAD).get()).data();
  assert.equal(lead.unreadCount, 1);
  assert.equal(lead.lastMessage, 'hello there');
  const m = await get(LEAD, 'SMin0001');
  assert.equal(m.direction, 'inbound');
  assert.equal(m.type, 'text');
  const conv = (await db.collection('outreachConversations').doc(LEAD).get()).data();
  assert.ok(conv.lastInboundAt);
});

test('window open after inbound: free text now sends', async () => {
  await svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgText0002', kind: 'text', body: 'reply!', replyToMessageId: 'SMin0001' });
  const call = twilioCalls.at(-1);
  assert.equal(call.Body, 'reply!');
  assert.equal(call.ContentSid, undefined);
  const m = await get(LEAD, 'msgText0002');
  assert.equal(m.replyToMessageId, 'SMin0001');
  assert.equal(m.status, 'sending');
});

test('inbound image: message created, media copied to Storage under the owner folder', async () => {
  const r = await svc.ingestInbound({
    sid: 'SMin0002', from: `whatsapp:${PHONE}`, body: '',
    media: [{ url: 'https://media.example/1', contentType: 'image/jpeg' }],
  });
  assert.equal(r.stored, true);
  const m = await get(LEAD, 'SMin0002');
  assert.equal(m.type, 'image');
  assert.equal(m.media.storagePath, `outreach_media/${OWNER}/${LEAD}/SMin0002/media_0.jpg`);
  assert.equal(m.media.size, 8);
  const lead = (await db.collection('outreachLeads').doc(LEAD).get()).data();
  assert.equal(lead.lastMessage, '📷 Photo');
  assert.equal(lead.unreadCount, 2);
});

test('inbound from unknown number is dropped unless a default owner is configured', async () => {
  const r = await svc.ingestInbound({ sid: 'SMin0003', from: 'whatsapp:+14155550000', body: 'who dis', media: [] });
  assert.equal(r.stored, false);
  process.env.OUTREACH_DEFAULT_OWNER_UID = 'ownerDefault';
  const r2 = await svc.ingestInbound({ sid: 'SMin0004', from: 'whatsapp:+14155550000', body: 'who dis', media: [] });
  assert.equal(r2.stored, true);
  assert.ok((await db.collection('outreachLeads').doc('ownerDefault_14155550000').get()).exists);
});

test('media send validates the stored object before touching Twilio', async () => {
  await assert.rejects(
    svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgMed00001', kind: 'media', media: { storagePath: 'outreach_media/other/x/y/a.png' } }),
    (e) => e.code === 'BAD_MEDIA_PATH',
  );
  await assert.rejects(
    svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: 'msgMed00001', kind: 'media', media: { storagePath: `outreach_media/${OWNER}/${LEAD}/msgMed00001/a.png` } }),
    (e) => e.code === 'MEDIA_NOT_FOUND',
  );
});

test('reactions: set, replace, remove, validated, owner-only', async () => {
  await svc.setReaction({ uid: OWNER, leadId: LEAD, messageId: 'SMin0001', emoji: '👍' });
  assert.deepEqual((await get(LEAD, 'SMin0001')).reactions, { [OWNER]: '👍' });
  await svc.setReaction({ uid: OWNER, leadId: LEAD, messageId: 'SMin0001', emoji: '❤️' });
  assert.equal((await get(LEAD, 'SMin0001')).reactions[OWNER], '❤️');
  await assert.rejects(svc.setReaction({ uid: OWNER, leadId: LEAD, messageId: 'SMin0001', emoji: 'hello' }), (e) => e.code === 'BAD_REACTION');
  await assert.rejects(svc.setReaction({ uid: 'intruder', leadId: LEAD, messageId: 'SMin0001', emoji: '👍' }), (e) => e.status === 403);
  await assert.rejects(svc.setReaction({ uid: OWNER, leadId: LEAD, messageId: 'nope', emoji: '👍' }), (e) => e.code === 'NOT_FOUND');
  await svc.setReaction({ uid: OWNER, leadId: LEAD, messageId: 'SMin0001', emoji: null });
  assert.deepEqual((await get(LEAD, 'SMin0001')).reactions ?? {}, {});
});

test('voice note: m4a upload is converted to OGG/Opus and that is what Twilio gets', async () => {
  const { default: ffmpeg } = await import('ffmpeg-static');
  const { execFileSync } = await import('node:child_process');
  const { readFileSync, mkdtempSync } = await import('node:fs');
  const { getStorage } = await import('firebase-admin/storage');
  const dir = mkdtempSync('/tmp/vn-');
  execFileSync(ffmpeg, ['-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2', '-c:a', 'aac', `${dir}/v.m4a`]);
  const id = 'msgVoice0001';
  const src = `outreach_media/${OWNER}/${LEAD}/${id}/voice_1.m4a`;
  const bucket = getStorage().bucket();
  await bucket.file(src).save(readFileSync(`${dir}/v.m4a`), { contentType: 'audio/mp4' });
  const before = twilioCalls.length;
  await svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: id, kind: 'media', body: 'ignored caption', media: { storagePath: src, mimeType: 'audio/mp4', durationMs: 2000, voice: true } });
  assert.equal(twilioCalls.length, before + 1);
  const m = await get(LEAD, id);
  assert.equal(m.type, 'audio');
  assert.equal(m.body, '', 'no caption on audio');
  assert.equal(m.media.storagePath, `outreach_media/${OWNER}/${LEAD}/${id}/voice.ogg`);
  assert.equal(m.media.playbackPath, src);
  assert.equal(m.media.mimeType, 'audio/ogg');
  assert.equal(m.media.voice, true);
  const [ogg] = await bucket.file(m.media.storagePath).download();
  assert.equal(ogg.subarray(0, 4).toString(), 'OggS');
  assert.ok(twilioCalls.at(-1).MediaUrl.includes('voice.ogg'));
  // A plain (non-voice) m4a is still rejected: only the recorder may produce it.
  const id2 = 'msgVoice0002';
  const src2 = `outreach_media/${OWNER}/${LEAD}/${id2}/a.m4a`;
  await bucket.file(src2).save(readFileSync(`${dir}/v.m4a`), { contentType: 'audio/mp4' });
  await assert.rejects(
    svc.sendOutbound({ uid: OWNER, leadId: LEAD, messageId: id2, kind: 'media', media: { storagePath: src2, mimeType: 'audio/mp4' } }),
    (e) => e.code === 'UNSUPPORTED_MEDIA',
  );
});

// ---- Cloud Functions layer: callable + webhooks ---------------------------------
test('callable: needs an approved account; unknown actions rejected', async () => {
  const { runAction } = await import('../index.js');
  await assert.rejects(runAction('stranger', 'ensureLead', { name: 'x', phoneNumber: '+971500000001' }), (e) => e.code === 'permission-denied');
  await db.collection('users').doc(OWNER).set({ approved: true });
  const r = await runAction(OWNER, 'ensureLead', { name: 'Via callable', phoneNumber: '+971500000002' });
  assert.equal(r.id, `${OWNER}_971500000002`);
  await assert.rejects(runAction(OWNER, 'nope', {}), (e) => e.code === 'invalid-argument' && e.details.code === 'BAD_ACTION');
  // domain errors keep their app-level code in `details`
  await assert.rejects(
    runAction(OWNER, 'text', { leadId: r.id, messageId: 'msgCall00001', body: 'hi' }),
    (e) => e.code === 'failed-precondition' && e.details.code === 'WINDOW_CLOSED',
  );
  await assert.rejects(runAction(OWNER, 'react', { leadId: `${OWNER}_nobody`, messageId: 'x', emoji: '👍' }), (e) => e.code === 'not-found');
});

test('webhook functions: signature required; signed requests store messages and statuses', async () => {
  const { default: express } = await import('express');
  const { twilioIncoming, twilioStatus } = await import('../index.js');
  const { computeTwilioSignature } = await import('./signature.js');
  const app = express();
  app.post('/twilioIncoming', twilioIncoming);
  app.post('/twilioStatus', twilioStatus);
  const server = await new Promise((r) => { const s = app.listen(0, () => r(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (path, form, headers = {}) => realFetch(base + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', ...headers },
    body: new URLSearchParams(form),
  });
  try {
    const form = { MessageSid: 'SMhttp001', From: `whatsapp:${PHONE}`, Body: 'via http', NumMedia: '0' };
    assert.equal((await post('/twilioIncoming', form)).status, 403);
    assert.equal((await post('/twilioIncoming', form, { 'X-Twilio-Signature': 'nope' })).status, 403);
    assert.equal((await msgs(LEAD).doc('SMhttp001').get()).exists, false);

    const sig = computeTwilioSignature('tok', `${process.env.PUBLIC_BASE_URL}/twilioIncoming`, form);
    const ok = await post('/twilioIncoming', form, { 'X-Twilio-Signature': sig });
    assert.equal(ok.status, 200);
    assert.match(await ok.text(), /<Response\/>/);
    assert.equal((await get(LEAD, 'SMhttp001')).body, 'via http');

    // the query string is part of the signed URL
    const stPath = `/twilioStatus?c=${LEAD}&m=msgText0002`;
    const stForm = { MessageSid: 'SM9', MessageStatus: 'delivered' };
    const stSig = computeTwilioSignature('tok', process.env.PUBLIC_BASE_URL + stPath, stForm);
    assert.equal((await post(stPath, stForm, { 'X-Twilio-Signature': stSig })).status, 204);
    assert.equal((await get(LEAD, 'msgText0002')).status, 'delivered');
    assert.equal((await post(stPath, stForm, { 'X-Twilio-Signature': 'bad' })).status, 403);
  } finally {
    server.close();
  }
});
