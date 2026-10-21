import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { DEFAULT_DAILY_LEAD_LIMIT, dayKey, dayStart, setWhatsAppLeadContacted, setWhatsAppLeadDealDone } from './leadContact.js';

// An in-memory stand-in for the parts of Firestore the module uses: documents,
// subcollections, and transactions that read before they write.
function fakeDb(seed, serverTime) {
  const docs = new Map(Object.entries(seed));
  // The time a serverTimestamp() is written as; each call moves it to its own `now`.
  const clock = { now: serverTime };
  const isSentinel = (v, s) => v && typeof v === 'object' && v.constructor === s.constructor;

  const toMs = (v) => (v?.toMillis ? v.toMillis() : v instanceof Date ? v.getTime() : v);
  const matches = (value, op, expected) => {
    if (op === '==') return value === expected;
    if (op === '>=') return toMs(value) >= toMs(expected);
    throw new Error(`unsupported operator ${op}`);
  };
  // A query over one top-level collection, as the transaction reads it.
  const query = (name, filters = []) => ({
    where: (field, op, value) => query(name, [...filters, { field, op, value }]),
    orderBy: () => query(name, filters),
    rows: () => [...docs.entries()]
      .filter(([path]) => path.startsWith(`${name}/`) && !path.slice(name.length + 1).includes('/'))
      .filter(([, data]) => filters.every((f) => matches(data[f.field], f.op, f.value)))
      .map(([path, data]) => ({ id: path.split('/').pop(), data: () => ({ ...data }) })),
  });

  const ref = (path) => ({
    path,
    collection: (name) => ({ doc: (id) => ref(`${path}/${name}/${id}`) }),
  });
  const read = (r) => ({ exists: docs.has(r.path), data: () => (docs.has(r.path) ? { ...docs.get(r.path) } : undefined) });
  const write = (r, patch) => {
    const next = { ...(docs.get(r.path) ?? {}) };
    for (const [k, v] of Object.entries(patch)) {
      if (isSentinel(v, FieldValue.delete())) delete next[k];
      else if (isSentinel(v, FieldValue.serverTimestamp())) next[k] = Timestamp.fromDate(clock.now);
      else next[k] = v;
    }
    docs.set(r.path, next);
  };

  const db = {
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`), where: (f, op, v) => query(name).where(f, op, v) }),
    runTransaction: async (fn) => fn({
      get: async (r) => {
        if (typeof r.rows !== 'function') return read(r);
        const rows = r.rows();
        return { docs: rows, size: rows.length };
      },
      update: write,
      set: write,
    }),
  };
  db.clock = clock;
  return { db, docs };
}

const DAY1 = new Date('2026-10-18T10:00:00Z'); // 13:00 in Qatar
const DAY2 = new Date('2026-10-19T10:00:00Z');

function seed({ limit, leads = 15, others = {} } = {}) {
  const data = {
    'users/me': { approved: true, ...(limit === undefined ? {} : { dailyLeadLimit: limit }) },
  };
  for (let i = 1; i <= leads; i++) data[`whatsappLeads/L${i}`] = { business: `Lead ${i}`, status: 'lead', sourceType: 'review' };
  return { ...data, ...others };
}

const contacted = (uid, when) => ({ business: 'Done', sourceType: 'review', status: 'contacted', contactedBy: uid, contactedAt: Timestamp.fromDate(when) });

const contact = (db, leadId, now, contacted = true) => {
  db.clock.now = now;
  return setWhatsAppLeadContacted({ uid: 'me', leadId, contacted, now, db });
};

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

test('a contacted lead becomes a deal done, and reopening it puts it back to Contacted', async () => {
  const { db, docs } = fakeDb(seed({ limit: 5 }), DAY1);
  await contact(db, 'L1', DAY1);
  const done = await setWhatsAppLeadDealDone({ uid: 'me', leadId: 'L1', done: true, db });
  assert.deepEqual(done, { dealDone: true, changed: true });
  assert.equal(docs.get('whatsappLeads/L1').status, 'dealDone');
  assert.ok(docs.get('whatsappLeads/L1').dealDoneAt);

  const again = await setWhatsAppLeadDealDone({ uid: 'me', leadId: 'L1', done: true, db });
  assert.deepEqual(again, { dealDone: true, changed: false });

  const reopened = await setWhatsAppLeadDealDone({ uid: 'me', leadId: 'L1', done: false, db });
  assert.deepEqual(reopened, { dealDone: false, changed: true });
  assert.equal(docs.get('whatsappLeads/L1').status, 'contacted');
  assert.equal('dealDoneAt' in docs.get('whatsappLeads/L1'), false);
});

test('only the salesman who contacted a lead can mark it a deal', async () => {
  const { db } = fakeDb(seed({ limit: 5 }), DAY1);
  await contact(db, 'L1', DAY1);
  const err = await failureOf(setWhatsAppLeadDealDone({ uid: 'someone-else', leadId: 'L1', done: true, db }));
  assert.equal(err.code, 'permission-denied');
});

test('a New lead cannot be marked a deal done before it is contacted', async () => {
  const { db } = fakeDb(seed({ limit: 5 }), DAY1);
  const err = await failureOf(setWhatsAppLeadDealDone({ uid: 'me', leadId: 'L2', done: true, db }));
  assert.equal(err.code, 'permission-denied'); // L2 has no contactedBy, so it is not this salesman's
});

test('a done deal cannot be moved back to New until it is reopened', async () => {
  const { db } = fakeDb(seed({ limit: 5 }), DAY1);
  await contact(db, 'L1', DAY1);
  await setWhatsAppLeadDealDone({ uid: 'me', leadId: 'L1', done: true, db });
  const err = await failureOf(setWhatsAppLeadContacted({ uid: 'me', leadId: 'L1', contacted: false, now: DAY1, db }));
  assert.equal(err.details.code, 'DEAL_DONE');
});

test('deal-done input is checked before any write', async () => {
  const { db } = fakeDb(seed(), DAY1);
  assert.equal((await failureOf(setWhatsAppLeadDealDone({ uid: 'me', leadId: '', done: true, db }))).code, 'invalid-argument');
  assert.equal((await failureOf(setWhatsAppLeadDealDone({ uid: 'me', leadId: 'L1', done: 'yes', db }))).code, 'invalid-argument');
  assert.equal((await failureOf(setWhatsAppLeadDealDone({ uid: 'me', leadId: 'missing', done: true, db }))).code, 'not-found');
});

test('the limit counts the leads contacted today, so a counter that has drifted cannot block a salesman', async () => {
  const data = seed({ limit: 3 });
  data['users/me/contactDays/2026-10-18'] = { count: 3 }; // drifted: says 3, but only 2 leads were contacted today
  data['whatsappLeads/L1'] = contacted('me', DAY1);
  data['whatsappLeads/L2'] = contacted('me', DAY1);
  const { db } = fakeDb(data, DAY1);
  assert.equal((await contact(db, 'L3', DAY1)).used, 3);
});

test('a contact made late at night in Qatar counts toward that day, not the next one', async () => {
  const data = seed({ limit: 2 });
  data['whatsappLeads/L1'] = contacted('me', new Date('2026-10-20T20:04:00Z')); // 23:04 on the 20th in Qatar
  data['whatsappLeads/L2'] = contacted('me', new Date('2026-10-20T20:30:00Z')); // 23:30 on the 20th in Qatar
  const { db } = fakeDb(data, DAY1);
  const today = new Date('2026-10-21T10:00:00Z'); // 13:00 on the 21st in Qatar
  assert.equal((await contact(db, 'L3', today)).used, 1);
});

test('a day starts at midnight in its own zone', () => {
  assert.equal(dayStart('2026-10-21', 'Asia/Qatar').toISOString(), '2026-10-20T21:00:00.000Z');
  assert.equal(dayStart('2026-10-21', 'Asia/Dubai').toISOString(), '2026-10-20T20:00:00.000Z');
});
