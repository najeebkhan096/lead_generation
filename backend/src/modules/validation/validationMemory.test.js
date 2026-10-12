import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  emailRetryAfter,
  isEmailCheckFresh,
  isWhatsAppCheckFresh,
  attachEmailChecks,
  EMAIL_RETRY_DAYS,
  WHATSAPP_RECHECK_DAYS,
} from './leadChecks.js';
import { leadDocId } from '../../lib/leadIdentity.js';
import {
  startEmailValidationJob,
  getEmailJobSnapshot,
  _resetEmailValidationJobForTests,
} from './email/emailValidationJob.js';
import {
  startValidationJob,
  getJobSnapshot,
  _resetValidationJobForTests,
} from './whatsapp/whatsappValidationJob.js';

const DAY = 24 * 60 * 60 * 1000;
const ago = (days) => ({ toMillis: () => Date.now() - days * DAY });

// ---- freshness rules -------------------------------------------------------

test('a found email is always fresh; negatives expire on their own schedule', () => {
  assert.equal(isEmailCheckFresh({ status: 'found', at: ago(400) }), true);
  assert.equal(isEmailCheckFresh({ status: 'none', at: ago(1) }), true);
  assert.equal(isEmailCheckFresh({ status: 'none', at: ago(EMAIL_RETRY_DAYS.none + 1) }), false);
  // a failed fetch is usually transient: it comes back sooner
  assert.equal(isEmailCheckFresh({ status: 'unreachable', at: ago(1) }), true);
  assert.equal(isEmailCheckFresh({ status: 'unreachable', at: ago(EMAIL_RETRY_DAYS.unreachable + 1) }), false);
  assert.equal(isEmailCheckFresh(undefined), false);
  assert.equal(emailRetryAfter({ status: 'found', at: ago(1) }), null);
  assert.ok(emailRetryAfter({ status: 'none', at: ago(0) }) > new Date());
});

test('a WhatsApp answer is reused for a while, either way', () => {
  assert.equal(isWhatsAppCheckFresh({ valid: true, at: ago(5) }), true);
  assert.equal(isWhatsAppCheckFresh({ valid: false, at: ago(5) }), true);
  assert.equal(isWhatsAppCheckFresh({ valid: false, at: ago(WHATSAPP_RECHECK_DAYS + 1) }), false);
  assert.equal(isWhatsAppCheckFresh({ at: ago(1) }), false, 'no answer recorded');
});

// ---- list decoration -------------------------------------------------------

test('lists carry "checked, nothing found" for leads without an email', async () => {
  const withMemory = { business: 'A', mapsUrl: 'https://maps.example/a' };
  const alreadyHasEmail = { business: 'B', mapsUrl: 'https://maps.example/b', email: 'x@b.example' };
  const neverChecked = { business: 'C', mapsUrl: 'https://maps.example/c' };
  const store = new Map([[leadDocId(withMemory), { email: { status: 'none', at: ago(3) } }]]);
  const db = {
    collection: () => ({ doc: (id) => ({ id }) }),
    getAll: async (...refs) =>
      refs.map((r) => ({ exists: store.has(r.id), data: () => store.get(r.id) })),
  };

  const out = await attachEmailChecks([withMemory, alreadyHasEmail, neverChecked], { db });
  assert.equal(out[0].emailCheck.status, 'none');
  assert.ok(out[0].emailCheck.retryAfter, 'tells the client when it becomes worth retrying');
  assert.equal(out[1].emailCheck, null, 'has an email');
  assert.equal(out[2].emailCheck, null, 'never checked');
});

// ---- the jobs remember every outcome ---------------------------------------

async function untilDone(snapshot) {
  while (snapshot()?.status === 'running') await new Promise((r) => setTimeout(r, 5));
  return snapshot();
}

test('email job records found / none / invalid / unreachable — not just the hits', async () => {
  _resetEmailValidationJobForTests();
  const recorded = {};
  const by = {
    ok: { emails: [{ email: 'a@ok.example', source: 'website' }], pagesFetched: 1 },
    bad: { emails: [{ email: 'a@bad.example', source: 'website' }], pagesFetched: 1 },
    none: { emails: [], pagesFetched: 2, lastError: 'No public email' },
    dead: { emails: [], pagesFetched: 0, lastError: 'HTTP 500' },
  };
  startEmailValidationJob({
    leads: ['ok', 'bad', 'none', 'dead'].map((id) => ({ id, business: id, website: `https://${id}.example` })),
    discoverFn: async (site) => by[new URL(site).hostname.split('.')[0]],
    verifyFn: async (e) => (e.includes('ok') ? { result: 'valid' } : { result: 'invalid', reason: 'no_mx' }),
    saveFn: async () => {},
    recordCheckFn: async (lead, check) => {
      recorded[lead.id] = check.status;
    },
  });
  await untilDone(getEmailJobSnapshot);
  assert.deepEqual(recorded, { ok: 'found', bad: 'invalid', none: 'none', dead: 'unreachable' });
});

test('a bookkeeping failure never breaks an email run', async () => {
  _resetEmailValidationJobForTests();
  startEmailValidationJob({
    leads: [{ id: 'a', business: 'A', website: 'https://a.example' }],
    discoverFn: async () => ({ emails: [], pagesFetched: 1 }),
    verifyFn: async () => ({ result: 'valid' }),
    saveFn: async () => {},
    recordCheckFn: async () => {
      throw new Error('firestore down');
    },
  });
  const snap = await untilDone(getEmailJobSnapshot);
  assert.equal(snap.status, 'done');
  assert.equal(snap.noEmailCount, 1);
});

test('an email run made only of reused answers completes at once, with them in the results', async () => {
  _resetEmailValidationJobForTests();
  const out = startEmailValidationJob({
    leads: [],
    reused: { x: { valid: true, email: 'x@x.example', emails: ['x@x.example'], source: 'website' } },
  });
  assert.equal(out.reused, 1);
  const snap = await untilDone(getEmailJobSnapshot);
  assert.equal(snap.status, 'done');
  assert.equal(snap.total, 0);
  assert.equal(snap.reusedCount, 1);
  assert.equal(snap.results.x.valid, true);
});

test('whatsapp job records both answers, and a run of only reused answers needs no session', async () => {
  _resetValidationJobForTests();
  const recorded = [];
  startValidationJob({
    leads: [
      { id: 'on', business: 'On', phone: '+15125550001' },
      { id: 'off', business: 'Off', phone: '+15125550002' },
    ],
    checkNumberFn: async (phone) => ({ checked: true, valid: phone.endsWith('1') }),
    updateLeadFn: async () => {},
    saveWhatsAppLeadsFn: async () => {},
    recordCheckFn: async (lead, check) => recorded.push([lead.id, check.valid]),
  });
  await untilDone(getJobSnapshot);
  assert.deepEqual(recorded, [['on', true], ['off', false]]);

  _resetValidationJobForTests();
  // default checker + nothing to check: must not demand a WhatsApp session
  const out = startValidationJob({ leads: [], reused: { known: { valid: true } } });
  assert.equal(out.reused, 1);
  const snap = await untilDone(getJobSnapshot);
  assert.equal(snap.status, 'done');
  assert.equal(snap.results.known.valid, true);
  assert.equal(snap.results.known.reused, true);
});
