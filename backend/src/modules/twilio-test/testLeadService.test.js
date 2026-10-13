import test from 'node:test';
import assert from 'node:assert/strict';
import { createTestLead, deleteTestLead, listTestLeads } from './testLeadService.js';

/** Just enough of Firestore for the service: docs by path, transactions, where(==), recursiveDelete. */
function fakeDb() {
  const store = new Map();
  const ref = (col, id) => ({
    col, id, path: `${col}/${id}`,
    get: async () => ({ exists: store.has(`${col}/${id}`), id, data: () => store.get(`${col}/${id}`) }),
    delete: async () => { store.delete(`${col}/${id}`); },
  });
  return {
    store,
    collection: (col) => ({
      doc: (id) => ref(col, id),
      where: (field, _op, value) => ({
        get: async () => ({
          docs: [...store.entries()]
            .filter(([k, v]) => k.startsWith(`${col}/`) && v[field] === value)
            .map(([k, v]) => ({ id: k.slice(col.length + 1), data: () => v })),
        }),
      }),
    }),
    runTransaction: async (fn) => fn({
      get: (r) => r.get(),
      set: (r, data, opts) => store.set(r.path, opts?.merge ? { ...store.get(r.path), ...data } : data),
    }),
    recursiveDelete: async (r) => { store.delete(r.path); },
  };
}

test('creates a test lead with the docs the mobile inbox reads', async () => {
  const db = fakeDb();
  const r = await createTestLead({ name: ' Ali ', businessName: 'Cafe', phoneNumber: '+971 50-123 4567', ownerId: 'uid1' }, { db });
  assert.equal(r.created, true);
  assert.equal(r.isTest, true);
  assert.equal(r.lead.id, 'uid1_971501234567');
  assert.equal(r.lead.phoneNumber, '+971501234567');
  assert.equal(r.lead.name, 'Ali');
  const lead = db.store.get('outreachLeads/uid1_971501234567');
  assert.equal(lead.isTest, true);
  assert.equal(lead.ownerId, 'uid1');
  assert.equal(db.store.get('outreachConversations/uid1_971501234567').leadId, 'uid1_971501234567');
});

test('falls back to the default owner and the number as name', async () => {
  const db = fakeDb();
  const r = await createTestLead({ phoneNumber: '+971501234567' }, { db });
  assert.equal(r.lead.ownerId, 'web-admin');
  assert.equal(r.lead.name, '+971501234567');
});

test('rejects bad numbers and unsafe owner ids', async () => {
  const db = fakeDb();
  await assert.rejects(createTestLead({ phoneNumber: '0501234567' }, { db }), (e) => e.code === 'INVALID_PHONE');
  await assert.rejects(createTestLead({ phoneNumber: '+971501234567', ownerId: 'a/b' }, { db }), (e) => e.code === 'INVALID_OWNER');
});

test('an existing real lead is left alone and reported as not a test lead', async () => {
  const db = fakeDb();
  db.store.set('outreachLeads/uid1_971501234567', { ownerId: 'uid1', name: 'Real', phoneNumber: '+971501234567' });
  const r = await createTestLead({ name: 'X', phoneNumber: '+971501234567', ownerId: 'uid1' }, { db });
  assert.equal(r.created, false);
  assert.equal(r.isTest, false);
  assert.equal(db.store.get('outreachLeads/uid1_971501234567').name, 'Real');
  assert.equal(db.store.get('outreachLeads/uid1_971501234567').isTest, undefined);
});

test('lists only test leads, newest first', async () => {
  const db = fakeDb();
  const mk = (n, t, isTest) => db.store.set(`outreachLeads/o_${n}`, {
    ownerId: 'o', name: `n${n}`, phoneNumber: `+97150000000${n}`, isTest, createdAt: { toMillis: () => t },
  });
  mk(1, 100, true);
  mk(2, 300, true);
  mk(3, 200, false);
  const leads = await listTestLeads({ db });
  assert.deepEqual(leads.map((l) => l.id), ['o_2', 'o_1']);
});

test('deletes a test lead with its conversation but refuses real or missing leads', async () => {
  const db = fakeDb();
  const t = await createTestLead({ phoneNumber: '+971501234567', ownerId: 'u' }, { db });
  await deleteTestLead(t.lead.id, { db });
  assert.equal(db.store.size, 0);

  db.store.set('outreachLeads/u_1', { ownerId: 'u', phoneNumber: '+971501234567' });
  await assert.rejects(deleteTestLead('u_1', { db }), (e) => e.code === 'NOT_A_TEST_LEAD');
  await assert.rejects(deleteTestLead('nope', { db }), (e) => e.code === 'LEAD_NOT_FOUND');
  await assert.rejects(deleteTestLead('', { db }), (e) => e.code === 'LEAD_NOT_FOUND');
  assert.ok(db.store.has('outreachLeads/u_1'));
});
