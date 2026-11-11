import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { startEmailValidationJob, getEmailJobSnapshot, cancelEmailValidationJob, _resetEmailValidationJobForTests } from './emailValidationJob.js';
import { SearchBlockedError } from './webSearchEmailDiscovery.js';
import { verifyEmailMx } from './emailVerificationService.js';

beforeEach(() => _resetEmailValidationJobForTests());

async function untilDone() {
  while (getEmailJobSnapshot()?.status === 'running') await new Promise((r) => setTimeout(r, 5));
  return getEmailJobSnapshot();
}

const found = (email, extra = {}) => ({
  emails: [{ email, source: 'web_search', score: 20, foundOn: 'https://x.example/p', ...extra }],
  primary: email,
  foundOn: 'https://x.example/p',
  searched: true,
  pagesFetched: 1,
});

test('a verified address is stored on the lead with where it was found', async () => {
  const updates = [];
  startEmailValidationJob({
    leads: [{ id: 'w1', business: "Joe's Pizza" }],
    discoverFn: async () => found('orders@joespizzatx.com'),
    verifyFn: async () => ({ result: 'valid', reason: 'mx_found' }),
    updateLeadFn: async (id, outcome) => updates.push([id, outcome]),
  });
  const snap = await untilDone();
  assert.equal(snap.status, 'done');
  assert.equal(snap.validCount, 1);
  assert.equal(snap.results.w1.email, 'orders@joespizzatx.com');
  assert.deepEqual(updates, [['w1', { status: 'found', email: 'orders@joespizzatx.com', emails: ['orders@joespizzatx.com'], source: 'web_search', foundOn: 'https://x.example/p' }]]);
});

test('an address that fails verification is not stored, and is counted as invalid', async () => {
  const updates = [];
  startEmailValidationJob({
    leads: [{ id: 'w1', business: 'Biz' }],
    discoverFn: async () => found('a@nowhere.example'),
    verifyFn: async () => ({ result: 'invalid', reason: 'no_mx' }),
    updateLeadFn: async (id, outcome) => updates.push([id, outcome]),
  });
  const snap = await untilDone();
  assert.equal(snap.invalidCount, 1);
  assert.equal(snap.validCount, 0);
  assert.deepEqual(updates, [['w1', { status: 'not_found' }]]);
});

test('no address found is remembered as not_found; a failed lookup as check_failed', async () => {
  const updates = {};
  startEmailValidationJob({
    leads: [{ id: 'a', business: 'A' }, { id: 'b', business: 'B' }],
    concurrency: 1,
    discoverFn: async (lead) => {
      if (lead.id === 'b') throw new Error('boom');
      return { emails: [], searched: true, pagesFetched: 2 };
    },
    verifyFn: async () => ({ result: 'valid' }),
    updateLeadFn: async (id, outcome) => { updates[id] = outcome.status; },
  });
  const snap = await untilDone();
  assert.equal(snap.noEmailCount, 1);
  assert.equal(snap.errorCount, 1);
  assert.deepEqual(updates, { a: 'not_found', b: 'check_failed' });
});

test('halts, without counting the refused lookup, when the search engine blocks', async () => {
  let calls = 0;
  startEmailValidationJob({
    leads: Array.from({ length: 8 }, (_, i) => ({ id: `w${i}`, business: `Biz ${i}` })),
    concurrency: 1,
    discoverFn: async () => {
      calls += 1;
      if (calls === 3) throw new SearchBlockedError();
      return { emails: [], searched: true, pagesFetched: 1 };
    },
    verifyFn: async () => ({ result: 'valid' }),
    updateLeadFn: async () => {},
  });
  const snap = await untilDone();
  assert.equal(calls, 3);
  assert.equal(snap.checked, 2);
  assert.match(snap.stoppedReason, /rate-limiting/);
});

test('a second job is refused while one runs, and cancel stops the run', async () => {
  let release;
  const gate = new Promise((r) => { release = r; });
  startEmailValidationJob({
    leads: [{ id: 'a', business: 'A' }, { id: 'b', business: 'B' }],
    concurrency: 1,
    discoverFn: async () => { await gate; return { emails: [], searched: true }; },
    updateLeadFn: async () => {},
  });
  assert.throws(() => startEmailValidationJob({ leads: [{ id: 'c', business: 'C' }] }), (e) => e.status === 409);
  assert.equal(cancelEmailValidationJob(), true);
  release();
  const snap = await untilDone();
  assert.equal(snap.status, 'cancelled');
  assert.equal(snap.checked, 1);
});

test('refuses a batch with nothing searchable', () => {
  assert.throws(() => startEmailValidationJob({ leads: [{ id: 'x' }] }), /can be searched/);
});

test('verifyEmailMx: syntax, disposable and MX outcomes', async () => {
  const mx = async () => [{ exchange: 'mx.example.com' }];
  assert.equal((await verifyEmailMx('a@example-biz.com', { resolveMx: mx })).result, 'valid');
  assert.equal((await verifyEmailMx('not-an-email', { resolveMx: mx })).result, 'invalid');
  assert.equal((await verifyEmailMx('a@mailinator.com', { resolveMx: mx })).result, 'risky');
  assert.equal((await verifyEmailMx('a@nomx.example', { resolveMx: async () => [] })).reason, 'no_mx');
  const enotfound = Object.assign(new Error('x'), { code: 'ENOTFOUND' });
  assert.equal((await verifyEmailMx('a@gone.example', { resolveMx: async () => { throw enotfound; } })).result, 'invalid');
  assert.equal((await verifyEmailMx('a@slow.example', { resolveMx: async () => { throw new Error('timeout'); } })).result, 'unknown');
});
