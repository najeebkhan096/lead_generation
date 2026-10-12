import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  startEmailValidationJob,
  getEmailJobSnapshot,
  cancelEmailValidationJob,
  _resetEmailValidationJobForTests,
} from './emailValidationJob.js';
import { leadsToXlsxBuffer, xlsxBufferToJson, sheetsToLeadsJson } from '../../archive/exportService.js';

async function untilDone(timeoutMs = 2000) {
  const start = Date.now();
  while (getEmailJobSnapshot()?.status === 'running') {
    if (Date.now() - start > timeoutMs) throw new Error('job did not finish');
    await new Promise((r) => setTimeout(r, 5));
  }
  return getEmailJobSnapshot();
}

const site = (id) => ({
  id,
  business: `Biz ${id}`,
  category: 'Cafe',
  website: `https://${id}.example`,
  mapsUrl: `https://maps.example/${id}`,
});

const found = (...addrs) => ({
  emails: addrs.map((email) => ({ email, source: 'contact_page', score: 50 })),
  primary: addrs[0] || null,
  emailSource: 'contact_page',
  pagesFetched: 2,
  lastError: null,
});

beforeEach(() => _resetEmailValidationJobForTests());

test('classifies each business and saves only verified emails', async () => {
  const saved = [];
  const discovery = {
    ok: found('info@ok.example'),
    bad: found('info@bad.example'),
    none: { emails: [], primary: null, pagesFetched: 3, lastError: 'No public email found on crawled pages' },
    dead: { emails: [], primary: null, pagesFetched: 0, lastError: 'HTTP 500' },
  };
  const out = startEmailValidationJob({
    leads: [site('ok'), site('bad'), site('none'), site('dead')],
    discoverFn: async (url) => discovery[new URL(url).hostname.split('.')[0]],
    verifyFn: async (email) =>
      email.endsWith('@ok.example')
        ? { result: 'valid', reason: 'mx_found' }
        : { result: 'invalid', reason: 'no_mx' },
    saveFn: async (leads) => saved.push(...leads),
  });
  assert.equal(out.total, 4);

  const snap = await untilDone();
  assert.equal(snap.status, 'done');
  assert.equal(snap.checked, 4);
  assert.equal(snap.validCount, 1);
  assert.equal(snap.invalidCount, 1);
  assert.equal(snap.noEmailCount, 1);
  assert.equal(snap.errorCount, 1);

  assert.equal(snap.results.ok.valid, true);
  assert.equal(snap.results.ok.email, 'info@ok.example');
  assert.equal(snap.results.bad.valid, false);
  assert.equal(snap.results.bad.reason, 'no_mx');
  assert.equal(snap.results.none.reason, 'no_email_found');
  assert.equal(snap.results.dead.error, 'HTTP 500');

  assert.equal(saved.length, 1);
  assert.equal(saved[0].business, 'Biz ok');
  assert.equal(saved[0].email, 'info@ok.example');
  assert.equal(saved[0].emailStatus, 'valid');
  assert.equal(saved[0].mapsUrl, 'https://maps.example/ok');
});

test('falls back to the next candidate when the best one is not deliverable', async () => {
  const saved = [];
  startEmailValidationJob({
    leads: [site('x')],
    discoverFn: async () => found('info@dead-domain.example', 'sales@live-domain.example'),
    verifyFn: async (email) =>
      email.includes('live') ? { result: 'valid' } : { result: 'invalid', reason: 'no_mx' },
    saveFn: async (l) => saved.push(...l),
  });
  const snap = await untilDone();
  assert.equal(snap.results.x.email, 'sales@live-domain.example');
  assert.equal(snap.validCount, 1);
  assert.equal(saved[0].email, 'sales@live-domain.example');
  assert.deepEqual(saved[0].emails, ['info@dead-domain.example', 'sales@live-domain.example']);
});

test('verifies a shared address once across the batch', async () => {
  let verifies = 0;
  startEmailValidationJob({
    leads: [site('a'), site('b'), site('c')],
    discoverFn: async () => found('hello@chain.example'),
    verifyFn: async () => {
      verifies += 1;
      return { result: 'valid' };
    },
    saveFn: async () => {},
    concurrency: 1,
  });
  const snap = await untilDone();
  assert.equal(snap.validCount, 3);
  assert.equal(verifies, 1);
});

test('skips businesses without a website and rejects a batch with none', async () => {
  assert.throws(
    () => startEmailValidationJob({ leads: [{ id: 'n', business: 'No Site', website: null }] }),
    /website/
  );
  const out = startEmailValidationJob({
    leads: [site('a'), { id: 'n', business: 'No Site', website: '' }],
    discoverFn: async () => found('a@a.example'),
    verifyFn: async () => ({ result: 'valid' }),
    saveFn: async () => {},
  });
  assert.equal(out.total, 1);
  assert.equal(out.skipped, 1);
  await untilDone();
});

test('only one job runs at a time; cancel stops the rest', async () => {
  let release;
  const gate = new Promise((r) => (release = r));
  startEmailValidationJob({
    leads: Array.from({ length: 6 }, (_, i) => site(`s${i}`)),
    discoverFn: async () => {
      await gate;
      return found('a@a.example');
    },
    verifyFn: async () => ({ result: 'valid' }),
    saveFn: async () => {},
    concurrency: 2,
  });
  assert.throws(
    () => startEmailValidationJob({ leads: [site('z')], discoverFn: async () => found('z@z.example') }),
    /already running/
  );
  assert.equal(cancelEmailValidationJob(), true);
  release();
  const snap = await untilDone();
  assert.equal(snap.status, 'cancelled');
  assert.ok(snap.checked < 6, `checked ${snap.checked}`);
});

test('a save failure is reported on the result, not thrown', async () => {
  startEmailValidationJob({
    leads: [site('a')],
    discoverFn: async () => found('a@a.example'),
    verifyFn: async () => ({ result: 'valid' }),
    saveFn: async () => {
      throw new Error('firestore down');
    },
  });
  const snap = await untilDone();
  assert.equal(snap.validCount, 1);
  assert.match(snap.results.a.error, /failed to save/);
});

test('email-verified workbook round-trips email columns; default workbook is unchanged', async () => {
  const leads = [
    { business: 'A', phone: '+1', category: 'Cafe', email: 'info@a.example', emailSource: 'contact_page',
      emails: ['info@a.example', 'sales@a.example'] },
  ];
  const withEmail = await xlsxBufferToJson(await leadsToXlsxBuffer([{ name: 'Cafe', leads }], { withEmail: true }));
  assert.ok(withEmail[0].headers.includes('Email'));
  const [back] = sheetsToLeadsJson(withEmail, 'p');
  assert.equal(back.email, 'info@a.example');
  assert.equal(back.emailSource, 'contact_page');
  assert.deepEqual(back.emails, ['info@a.example', 'sales@a.example']);

  const plain = await xlsxBufferToJson(await leadsToXlsxBuffer([{ name: 'Cafe', leads }]));
  assert.ok(!plain[0].headers.includes('Email'));
  assert.equal(sheetsToLeadsJson(plain, 'p')[0].email, null);
});
