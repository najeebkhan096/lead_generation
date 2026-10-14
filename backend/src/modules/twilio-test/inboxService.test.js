import test from 'node:test';
import assert from 'node:assert/strict';
import { inboxService } from './inboxService.js';

const ts = (ms) => ({ toMillis: () => ms });

/** Docs by path; where(==).limit().get(), doc().get()/update(), doc().collection(). */
function fakeDb(docs = {}) {
  const store = new Map(Object.entries(docs));
  const docRef = (path) => ({
    get: async () => ({ exists: store.has(path), id: path.split('/').pop(), data: () => store.get(path) }),
    update: async (patch) => { store.set(path, { ...store.get(path), ...patch }); },
    collection: (name) => collectionRef(`${path}/${name}`),
  });
  const collectionRef = (path) => ({
    doc: (id) => docRef(`${path}/${id}`),
    where: (field, _op, value) => {
      const run = async () => ({
        docs: [...store.entries()]
          .filter(([k, v]) => k.startsWith(`${path}/`) && !k.slice(path.length + 1).includes('/') && v[field] === value)
          .map(([k, v]) => ({ id: k.slice(path.length + 1), data: () => v })),
      });
      return { get: run, limit: () => ({ get: run }) };
    },
  });
  return { store, collection: (name) => collectionRef(name) };
}

const config = () => ({ whatsappNumber: '+14155550100' });
const wa = (sid, from, body, extra = {}) => ({
  sid, direction: 'inbound', from: `whatsapp:${from}`, to: 'whatsapp:+14155550100', body, date_sent: '2026-10-14T10:00:00Z', ...extra,
});

function makeService(db, messages, { ingested = [], created = [] } = {}) {
  return inboxService({
    db: () => db,
    config,
    listTwilioMessages: async () => messages,
    listTwilioMedia: async () => [],
    ensureLead: async (a) => {
      const id = `${a.ownerId}_${a.phoneNumber.replace(/\D/g, '')}`;
      created.push(a);
      db.store.set(`outreachLeads/${id}`, { ownerId: a.ownerId, phoneNumber: a.phoneNumber, businessName: a.businessName, name: a.name });
      return { id, created: true };
    },
    ingestInbound: async (a) => {
      ingested.push(a.sid);
      return { stored: true };
    },
  });
}

test('a message from an unknown number becomes a lead named from the prefilled text', async () => {
  const db = fakeDb();
  const created = [];
  const ingested = [];
  const svc = makeService(db, [wa('SM1', '+12089574765', 'Hi, I got your email about Acme Plumbing.')], { created, ingested });
  const r = await svc.sync();

  assert.deepEqual(r, { ingested: 1, newLeads: 1 });
  assert.equal(created[0].businessName, 'Acme Plumbing');
  assert.equal(created[0].phoneNumber, '+12089574765');
  assert.deepEqual(ingested, ['SM1']);
  const lead = [...db.store.entries()].find(([k]) => k.startsWith('outreachLeads/'))[1];
  assert.equal(lead.source, 'whatsapp-inbound');
  assert.equal(lead.repliedViaLink, true);
});

test('a known number is not duplicated and is flagged as replied', async () => {
  const db = fakeDb({ 'outreachLeads/uidX_12089574765': { ownerId: 'uidX', phoneNumber: '+12089574765' } });
  const created = [];
  const svc = makeService(db, [wa('SM2', '+12089574765', 'hello')], { created });
  const r = await svc.sync();

  assert.deepEqual(r, { ingested: 1, newLeads: 0 });
  assert.equal(created.length, 0);
  assert.equal(db.store.get('outreachLeads/uidX_12089574765').repliedViaLink, true);
});

test('messages already stored are skipped', async () => {
  const db = fakeDb({
    'outreachLeads/uidX_12089574765': { ownerId: 'uidX', phoneNumber: '+12089574765', repliedViaLink: true },
    'outreachConversations/uidX_12089574765/messages/SM3': { body: 'old' },
  });
  const ingested = [];
  const svc = makeService(db, [wa('SM3', '+12089574765', 'old')], { ingested });
  assert.deepEqual(await svc.sync(), { ingested: 0, newLeads: 0 });
  assert.deepEqual(ingested, []);
});

test('only inbound WhatsApp messages count', async () => {
  const db = fakeDb();
  const ingested = [];
  const svc = makeService(db, [
    { ...wa('SM4', '+12089574765', 'ours'), direction: 'outbound-api' },
    { ...wa('SM5', '+12089574765', 'sms'), from: '+12089574765' },
    wa('SM6', 'not-a-number', 'junk'),
  ], { ingested });
  assert.deepEqual(await svc.sync(), { ingested: 0, newLeads: 0 });
});

test('sync explains a missing WhatsApp number', async () => {
  const svc = inboxService({ db: () => fakeDb(), config: () => ({ whatsappNumber: '' }) });
  await assert.rejects(svc.sync(), (e) => e.code === 'NOT_CONFIGURED');
});

test('list returns replied leads, most recent first', async () => {
  const db = fakeDb({
    'outreachLeads/a': { ownerId: 'o', phoneNumber: '+1', repliedViaLink: true, lastMessageAt: ts(100), lastMessage: 'old', unreadCount: 0 },
    'outreachLeads/b': { ownerId: 'o', phoneNumber: '+2', repliedViaLink: true, lastMessageAt: ts(300), lastMessage: 'new', unreadCount: 2 },
    'outreachLeads/c': { ownerId: 'o', phoneNumber: '+3', isTest: true },
  });
  const leads = await inboxService({ db: () => db }).list();
  assert.deepEqual(leads.map((l) => l.id), ['b', 'a']);
  assert.equal(leads[0].unreadCount, 2);
  assert.equal(leads[0].lastMessage, 'new');
});
