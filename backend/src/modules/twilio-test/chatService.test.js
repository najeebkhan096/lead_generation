import test from 'node:test';
import assert from 'node:assert/strict';
import { chatService, decodeImage, messageJson } from './chatService.js';

const ts = (ms) => ({ toMillis: () => ms });

/** Docs by path; supports doc().get(), doc().collection(), and collection().orderBy().limit().get(). */
function fakeDb(docs) {
  const store = new Map(Object.entries(docs));
  const docRef = (path) => ({
    get: async () => ({ exists: store.has(path), id: path.split('/').pop(), data: () => store.get(path) }),
    update: async (patch) => { store.set(path, { ...store.get(path), ...patch }); },
    collection: (name) => collectionRef(`${path}/${name}`),
  });
  const collectionRef = (path) => ({
    doc: (id) => docRef(`${path}/${id}`),
    orderBy: (field, dir = 'asc') => ({
      limit: (n) => ({
        get: async () => {
          const rows = [...store.entries()]
            .filter(([k]) => k.startsWith(`${path}/`) && !k.slice(path.length + 1).includes('/'))
            .map(([k, v]) => ({ id: k.slice(path.length + 1), data: () => v }))
            .sort((a, b) => (a.data()[field].toMillis() - b.data()[field].toMillis()) * (dir === 'desc' ? -1 : 1));
          return { docs: rows.slice(0, n) };
        },
      }),
    }),
  });
  return { store, collection: (name) => collectionRef(name) };
}

const LEAD = { ownerId: 'uid1', phoneNumber: '+971501234567', isTest: true };
const base = (extra = {}) => ({
  'outreachLeads/L1': LEAD,
  'outreachConversations/L1': {},
  ...extra,
});

test('getChat: oldest first, hides deleted, reports the open window', async () => {
  const now = Date.now();
  const db = fakeDb(base({
    'outreachConversations/L1': { lastInboundAt: ts(now - 60_000) },
    'outreachConversations/L1/messages/b': { direction: 'outbound', body: 'second', status: 'sent', createdAt: ts(2000) },
    'outreachConversations/L1/messages/a': { direction: 'inbound', body: 'first', status: 'delivered', createdAt: ts(1000) },
    'outreachConversations/L1/messages/c': { direction: 'outbound', body: 'gone', createdAt: ts(3000), deletedAt: ts(3500) },
  }));
  const chat = await chatService({ db: () => db }).getChat('L1');
  assert.deepEqual(chat.messages.map((m) => m.id), ['a', 'b']);
  assert.equal(chat.messages[0].direction, 'inbound');
  assert.ok(chat.windowClosesAt > now);
});

test('getChat: window is null when closed or never opened', async () => {
  const db = fakeDb(base({ 'outreachConversations/L1': { lastInboundAt: ts(Date.now() - 25 * 3600_000) } }));
  assert.equal((await chatService({ db: () => db }).getChat('L1')).windowClosesAt, null);
  const db2 = fakeDb(base());
  assert.equal((await chatService({ db: () => db2 }).getChat('L1')).windowClosesAt, null);
});

test('real leads and unknown ids are refused', async () => {
  const db = fakeDb({ 'outreachLeads/R1': { ownerId: 'uid1', phoneNumber: '+971501234567' } });
  const svc = chatService({ db: () => db });
  await assert.rejects(svc.getChat('R1'), (e) => e.code === 'NOT_A_TEST_LEAD');
  await assert.rejects(svc.sendText('R1', { kind: 'sms', body: 'x' }), (e) => e.code === 'NOT_A_TEST_LEAD');
  await assert.rejects(svc.sync('R1'), (e) => e.code === 'NOT_A_TEST_LEAD');
  await assert.rejects(svc.getChat('nope'), (e) => e.code === 'LEAD_NOT_FOUND');
});

test('leads that replied on WhatsApp can be chatted with and are marked read when opened', async () => {
  const db = fakeDb({
    'outreachLeads/W1': { ownerId: 'uid1', phoneNumber: '+12089574765', repliedViaLink: true, unreadCount: 2 },
    'outreachConversations/W1': { lastInboundAt: ts(Date.now() - 1000) },
  });
  const chat = await chatService({ db: () => db }).getChat('W1');
  assert.ok(chat.windowClosesAt > Date.now());
  assert.equal(db.store.get('outreachLeads/W1').unreadCount, 0);
});

test('sendText sends as the lead owner and rejects unknown kinds', async () => {
  const sent = [];
  const db = fakeDb(base());
  const svc = chatService({
    db: () => db,
    sendOutbound: async (args) => {
      sent.push(args);
      db.collection('outreachConversations').doc('L1').collection('messages');
    },
  });
  // The message doc does not exist in this fake, so reading it back is a 404.
  await assert.rejects(svc.sendText('L1', { kind: 'sms', body: 'hello' }), (e) => e.code === 'NOT_FOUND');
  assert.equal(sent[0].uid, 'uid1');
  assert.equal(sent[0].leadId, 'L1');
  assert.equal(sent[0].kind, 'sms');
  assert.equal(sent[0].body, 'hello');
  assert.match(sent[0].messageId, /^[A-Za-z0-9]{32}$/);
  await assert.rejects(svc.sendText('L1', { kind: 'media', body: 'x' }), (e) => e.code === 'BAD_KIND');
});

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(16)]);

test('decodeImage validates type, signature and size', () => {
  assert.equal(decodeImage(JPEG.toString('base64'), 'image/jpeg').ext, 'jpg');
  assert.equal(decodeImage(`data:image/jpeg;base64,${JPEG.toString('base64')}`, 'image/jpeg').bytes.length, JPEG.length);
  assert.throws(() => decodeImage(JPEG.toString('base64'), 'image/gif'), (e) => e.code === 'UNSUPPORTED_MEDIA');
  assert.throws(() => decodeImage(JPEG.toString('base64'), 'image/png'), (e) => e.code === 'UNSUPPORTED_MEDIA');
  assert.throws(() => decodeImage('', 'image/jpeg'), (e) => e.code === 'EMPTY');
  assert.throws(
    () => decodeImage(Buffer.concat([JPEG, Buffer.alloc(5 * 1024 * 1024)]).toString('base64'), 'image/jpeg'),
    (e) => e.code === 'MEDIA_TOO_LARGE',
  );
});

test('sendTemplate uploads the image into the owner folder and sends its download URL', async () => {
  const saved = [];
  const sent = [];
  const db = fakeDb(base());
  const bucket = {
    file: (path) => ({ name: path, bucket: { name: 'proj.firebasestorage.app' }, save: async (bytes, o) => saved.push({ path, bytes, o }) }),
  };
  const svc = chatService({ db: () => db, bucket: () => bucket, sendOutbound: async (a) => { sent.push(a); } });
  await assert.rejects(
    svc.sendTemplate('L1', { imageBase64: JPEG.toString('base64'), mimeType: 'image/jpeg', channel: 'sms' }),
    (e) => e.code === 'NOT_FOUND', // message doc is not created by the fake sender
  );
  assert.match(saved[0].path, /^outreach_images\/uid1\/\d+_[0-9a-f]{8}\.jpg$/);
  assert.equal(saved[0].o.contentType, 'image/jpeg');
  assert.equal(sent[0].kind, 'template');
  assert.equal(sent[0].channel, 'sms');
  assert.ok(sent[0].mediaUrl.startsWith('https://firebasestorage.googleapis.com/v0/b/proj.firebasestorage.app/o/outreach_images%2Fuid1%2F'));
  assert.match(sent[0].mediaUrl, /\?alt=media&token=[0-9a-f-]{36}$/);
});

test('sync refreshes open statuses and stores only unseen replies (WhatsApp and SMS)', async () => {
  const db = fakeDb(base({
    'outreachConversations/L1/messages/m1': { direction: 'outbound', twilioSid: 'SM1', status: 'sent', channel: 'whatsapp', createdAt: ts(1000) },
    'outreachConversations/L1/messages/m2': { direction: 'outbound', twilioSid: 'SM2', status: 'delivered', channel: 'sms', createdAt: ts(2000) },
    'outreachConversations/L1/messages/SMold': { direction: 'inbound', status: 'delivered', createdAt: ts(500) },
  }));
  const fetched = [];
  const applied = [];
  const ingested = [];
  const svc = chatService({
    db: () => db,
    fetchTwilioMessage: async (sid) => { fetched.push(sid); return { sid, status: 'delivered' }; },
    applyStatusCallback: async (a) => { applied.push(a.messageId); return { applied: true }; },
    listTwilioMessages: async (q) => (q.From.startsWith('whatsapp:')
      ? [
        { sid: 'SMold', direction: 'inbound', body: 'seen', from: 'whatsapp:+971501234567', date_sent: '2026-10-13T10:00:00Z' },
        { sid: 'SMnew', direction: 'inbound', body: 'hi', from: 'whatsapp:+971501234567', date_sent: '2026-10-13T11:00:00Z' },
        { sid: 'SMout', direction: 'outbound-api', body: 'ours', from: 'whatsapp:+14155550000', date_sent: '2026-10-13T11:30:00Z' },
      ]
      : [{ sid: 'SMsms', direction: 'inbound', body: 'by sms', from: '+971501234567', date_sent: '2026-10-13T12:00:00Z' }]),
    listTwilioMedia: async () => [],
    ingestInbound: async (a) => { ingested.push(a.sid); return { stored: true }; },
  });
  const r = await svc.sync('L1');
  assert.deepEqual(fetched, ['SM1']); // m2 is a delivered SMS: nothing more to learn
  assert.deepEqual(applied, ['m1']);
  assert.deepEqual(ingested, ['SMnew', 'SMsms']);
  assert.deepEqual(r, { statusUpdates: 1, ingested: 2 });
});

test('sync keeps going when a status lookup fails', async () => {
  const db = fakeDb(base({
    'outreachConversations/L1/messages/m1': { direction: 'outbound', twilioSid: 'SM1', status: 'sent', channel: 'whatsapp', createdAt: ts(1000) },
  }));
  const svc = chatService({
    db: () => db,
    fetchTwilioMessage: async () => { throw new Error('boom'); },
    listTwilioMessages: async () => [{ sid: 'SMx', direction: 'inbound', body: 'hi', from: 'whatsapp:+971501234567' }],
    ingestInbound: async () => ({ stored: true }),
  });
  assert.deepEqual(await svc.sync('L1'), { statusUpdates: 0, ingested: 1 });
});

test('messageJson maps a stored document', () => {
  const j = messageJson('x', {
    direction: 'outbound', type: 'template', channel: 'sms', body: 'hi', status: 'failed', errorCode: 21612,
    errorMessage: 'nope', createdAt: ts(5), media: { fileName: 'a.jpg' },
  });
  assert.deepEqual(j, {
    id: 'x', direction: 'outbound', type: 'template', channel: 'sms', body: 'hi', status: 'failed',
    errorCode: 21612, errorMessage: 'nope', createdAt: 5, mediaName: 'a.jpg',
  });
});
