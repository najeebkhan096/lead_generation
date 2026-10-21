import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { DEFAULT_DAILY_LEAD_LIMIT, dayKey, setWhatsAppLeadContacted } from './leadContact.js';

// An in-memory stand-in for the parts of Firestore the module uses: documents,
// subcollections, and transactions that read before they write.
function fakeDb(seed, serverTime) {
  const docs = new Map(Object.entries(seed));
  const isSentinel = (v, s) => v && typeof v === 'object' && v.constructor === s.constructor;

  const ref = (path) => ({
    path,
    collection: (name) => ({ doc: (id) => ref(`${path}/${name}/${id}`) }),
  });
  const read = (r) => ({ exists: docs.has(r.path), data: () => (docs.has(r.path) ? { ...docs.get(r.path) } : undefined) });
  const write = (r, patch) => {
    const next = { ...(docs.get(r.path) ?? {}) };
    for (const [k, v] of Object.entries(patch)) {
      if (isSentinel(v, FieldValue.delete())) delete next[k];
      else if (isSentinel(v, FieldValue.serverTimestamp())) next[k] = Timestamp.fromDate(serverTime);
      else next[k] = v;
    }
    docs.set(r.path, next);
  };

  const db = {
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }),
    runTransaction: async (fn) => fn({
      get: async (r) => read(r),
      update: write,
      set: write,
    }),
  };
  return { db, docs };
}

const DAY1 = new Date('2026-10-18T10:00:00Z'); // 13:00 in Qatar
const DAY2 = new Date('2026-10-19T10:00:00Z');

function seed({ limit, leads = 15, others = {} } = {}) {
  const data = {
    'users/me': { approved: true, ...(limit === undefined ? {} : { dailyLeadLimit: limit }) },
  };
  for (let i = 1; i <= leads; i++) data[`whatsappLeads/L${i}`] = { business: `Lead ${i}`, status: 'lead' };
  return { ...data, ...others };
}

const contact = (db, leadId, now, contacted = true) =>
  setWhatsAppLeadContacted({ uid: 'me', leadId, contacted, now, db });

async function failureOf(promise) {
  try {
    await promise;
  } catch (err) {
    return err;
  }
  assert.fail('expected the call to be refused');
}

test('a salesman can contact up to the default limit a day, then is stopped', async () => {
  const { db } = fakeDb(seed(), DAY1);
  for (let i = 1; i <= DEFAULT_DAILY_LEAD_LIMIT; i++) {
    assert.equal((await contact(db, `L${i}`, DAY1)).used, i);
  }
  const err = await failureOf(contact(db, 'L11', DAY1));
  assert.equal(err.code, 'resource-exhausted');
  assert.equal(err.details.code, 'DAILY_LIMIT');
  assert.equal(err.details.limit, DEFAULT_DAILY_LEAD_LIMIT);
});

test('an admin-set limit replaces the default', async () => {
  const { db } = fakeDb(seed({ limit: 2 }), DAY1);
  await contact(db, 'L1', DAY1);
  await contact(db, 'L2', DAY1);
  const err = await failureOf(contact(db, 'L3', DAY1));
  assert.equal(err.details.limit, 2);
});

test('a limit of zero stops every new contact', async () => {
  const { db } = fakeDb(seed({ limit: 0 }), DAY1);
  const err = await failureOf(contact(db, 'L1', DAY1));
  assert.equal(err.details.code, 'DAILY_LIMIT');
});

test('re-marking a lead you already contacted does not count again', async () => {
  const { db, docs } = fakeDb(seed({ limit: 2 }), DAY1);
  await contact(db, 'L1', DAY1);
  const again = await contact(db, 'L1', DAY1);
  assert.equal(again.counted, false);
  assert.equal(docs.get('users/me/contactDays/2026-10-18').count, 1);
});

test('a lead another salesman contacted is refused', async () => {
  const { db } = fakeDb(seed({ others: { 'whatsappLeads/L1': { status: 'contacted', contactedBy: 'other' } } }), DAY1);
  const err = await failureOf(contact(db, 'L1', DAY1));
  assert.equal(err.code, 'failed-precondition');
  assert.equal(err.details.code, 'TAKEN');
});

test('moving a lead back to New frees today’s slot', async () => {
  const { db } = fakeDb(seed({ limit: 1 }), DAY1);
  await contact(db, 'L1', DAY1);
  await failureOf(contact(db, 'L2', DAY1));

  const back = await contact(db, 'L1', DAY1, false);
  assert.equal(back.counted, true);
  assert.equal((await contact(db, 'L2', DAY1)).used, 1);
});

test('only the salesman who contacted a lead can move it back', async () => {
  const { db } = fakeDb(seed({ others: { 'whatsappLeads/L1': { status: 'contacted', contactedBy: 'other' } } }), DAY1);
  const err = await failureOf(contact(db, 'L1', DAY1, false));
  assert.equal(err.details.code, 'NOT_YOURS');
});

test('the limit starts over on the next day', async () => {
  const { db } = fakeDb(seed({ limit: 1 }), DAY1);
  await contact(db, 'L1', DAY1);
  await failureOf(contact(db, 'L2', DAY1));
  assert.equal((await contact(db, 'L2', DAY2)).used, 1);
});

test('moving back a lead contacted on an earlier day does not free today’s slot', async () => {
  const { db } = fakeDb(seed({ limit: 1 }), DAY1);
  await contact(db, 'L1', DAY1);
  await contact(db, 'L2', DAY2); // today's one allowed contact
  await contact(db, 'L1', DAY2, false); // undoing yesterday's contact
  const err = await failureOf(contact(db, 'L3', DAY2));
  assert.equal(err.details.code, 'DAILY_LIMIT');
});

test('days are counted in the configured zone, not UTC', () => {
  const lateUtc = new Date('2026-10-18T22:30:00Z'); // 01:30 on the 19th in Qatar
  assert.equal(dayKey(lateUtc, 'Asia/Qatar'), '2026-10-19');
  assert.equal(dayKey(lateUtc, 'America/Chicago'), '2026-10-18');
});

test('the default day is Qatar: a contact at 23:30 Qatar time is still that day', () => {
  // 23:30 on the 20th in Qatar is 00:30 on the 21st in Dubai, which used to count as the 21st.
  assert.equal(dayKey(new Date('2026-10-20T20:30:00Z')), '2026-10-20');
  assert.equal(dayKey(new Date('2026-10-20T21:00:00Z')), '2026-10-21');
});

test('bad input and unknown leads are refused before any write', async () => {
  const { db } = fakeDb(seed(), DAY1);
  assert.equal((await failureOf(setWhatsAppLeadContacted({ uid: 'me', leadId: '', contacted: true, now: DAY1, db }))).code, 'invalid-argument');
  assert.equal((await failureOf(setWhatsAppLeadContacted({ uid: 'me', leadId: 'L1', contacted: 'yes', now: DAY1, db }))).code, 'invalid-argument');
  assert.equal((await failureOf(contact(db, 'missing', DAY1))).code, 'not-found');
});
