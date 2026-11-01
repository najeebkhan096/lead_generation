import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createEmailQueue } from './emailQueue.js';
import { leadDocId } from '../../lib/leadIdentity.js';

const site = (n, extra = {}) => ({
  business: `Biz ${n}`,
  location: 'Texas',
  mapsUrl: `https://www.google.com/maps/place/biz-${n}`,
  website: `https://biz${n}.test/`,
  ...extra,
});
const FOUND = { status: 'found', reason: null, website: 'https://x.test/', emails: [{ address: 'a@x.test', sourceUrl: 'https://x.test/' }] };

function harness(overrides = {}) {
  const calls = { crawl: [], save: [], mark: [], record: [] };
  const logs = [];
  const queue = createEmailQueue({
    concurrency: 2,
    sleep: async () => {},
    log: (m, level = 'info') => logs.push([level, m]),
    getChecksFn: async () => new Map(),
    crawlFn: async (url) => {
      calls.crawl.push(url);
      return FOUND;
    },
    saveEmailFn: async (s, r) => {
      calls.save.push([s.business, r.status]);
      return 'inserted';
    },
    markAvailableFn: async (s) => calls.mark.push(s.business),
    recordCheckFn: async (s, c) => calls.record.push([s.business, c.status, c.reason]),
    ...overrides,
  });
  return { queue, calls, logs };
}

test('a found email is saved, the site marked available, and the check remembered', async () => {
  const { queue, calls, logs } = harness();
  assert.equal(queue.enqueue(site(1)), 'queued');
  await queue.onIdle();
  assert.deepEqual(calls.save, [['Biz 1', 'found']]);
  assert.deepEqual(calls.mark, ['Biz 1']);
  assert.deepEqual(calls.record, [['Biz 1', 'found', null]]);
  assert.equal(queue.snapshot().found, 1);
  assert.ok(logs.some(([, m]) => /started: biz1\.test/.test(m)));
  assert.ok(logs.some(([, m]) => /email found: biz1\.test — 1 address \(lead saved\)/.test(m)));
  assert.ok(!logs.some(([, m]) => m.includes('a@x.test')), 'addresses are not logged');
});

test('no email published: remembered as not_found, nothing saved as a lead', async () => {
  const { queue, calls, logs } = harness({ crawlFn: async () => ({ status: 'not_found', reason: null, emails: [], website: 'https://biz1.test/' }) });
  queue.enqueue(site(1));
  await queue.onIdle();
  assert.deepEqual(calls.save, []);
  assert.deepEqual(calls.record, [['Biz 1', 'not_found', null]]);
  assert.ok(logs.some(([, m]) => /no email published/.test(m)));
});

test('a transient failure is retried, then succeeds', async () => {
  let n = 0;
  const { queue, calls, logs } = harness({
    crawlFn: async () => (++n === 1 ? { status: 'check_failed', reason: 'timeout', emails: [] } : FOUND),
  });
  queue.enqueue(site(1));
  await queue.onIdle();
  assert.equal(n, 2);
  assert.deepEqual(calls.save, [['Biz 1', 'found']]);
  assert.ok(logs.some(([level, m]) => level === 'warn' && /retrying: biz1\.test \(timeout\)/.test(m)));
});

test('a permanent failure is logged and recorded as check_failed; it does not throw', async () => {
  const { queue, calls, logs } = harness({ crawlFn: async () => ({ status: 'check_failed', reason: 'timeout', emails: [] }) });
  queue.enqueue(site(1));
  await queue.onIdle();
  assert.deepEqual(calls.record, [['Biz 1', 'check_failed', 'timeout']]);
  assert.equal(queue.snapshot().checkFailed, 1);
  assert.ok(logs.some(([, m]) => /permanently failed: biz1\.test/.test(m)));
});

test('a blocked site is not retried', async () => {
  let n = 0;
  const { queue } = harness({ crawlFn: async () => (n++, { status: 'check_failed', reason: 'blocked', emails: [] }) });
  queue.enqueue(site(1));
  await queue.onIdle();
  assert.equal(n, 1);
});

test('one site crashing does not stop the others', async () => {
  const { queue, calls } = harness({
    crawlFn: async (url) => {
      if (url.includes('biz1')) throw new Error('boom');
      return FOUND;
    },
  });
  queue.enqueue(site(1));
  queue.enqueue(site(2));
  queue.enqueue(site(3));
  await queue.onIdle();
  assert.deepEqual(calls.save.map(([b]) => b).sort(), ['Biz 2', 'Biz 3']);
  assert.equal(queue.snapshot().errors, 1);
});

test('a failing database write is contained', async () => {
  const { queue, logs } = harness({ saveEmailFn: async () => { throw new Error('firestore down'); } });
  queue.enqueue(site(1));
  await queue.onIdle();
  assert.ok(logs.some(([level, m]) => level === 'warn' && /firestore down/.test(m)));
});

test('one business is looked up once, even if offered twice', async () => {
  const { queue, calls } = harness();
  assert.equal(queue.enqueue(site(1)), 'queued');
  assert.equal(queue.enqueue(site(1)), 'duplicate');
  await queue.onIdle();
  assert.equal(calls.crawl.length, 1);
});

test('a recently checked business is skipped without a request', async () => {
  const { queue, calls, logs } = harness({
    getChecksFn: async ([s]) => new Map([[leadDocId(s), { email: { status: 'not_found', at: { toMillis: () => Date.now() - 86400000 } } }]]),
  });
  queue.enqueue(site(1));
  await queue.onIdle();
  assert.equal(calls.crawl.length, 0);
  assert.equal(queue.snapshot().skippedRecent, 1);
  assert.ok(logs.some(([, m]) => /duplicate skipped/.test(m)));
});

test('only `concurrency` lookups run at once, and the backlog is capped', async () => {
  let running = 0;
  let peak = 0;
  const release = [];
  const { queue } = harness({
    maxPending: 3,
    crawlFn: async () => {
      running += 1;
      peak = Math.max(peak, running);
      await new Promise((r) => release.push(r));
      running -= 1;
      return FOUND;
    },
  });
  const results = [1, 2, 3, 4, 5, 6].map((n) => queue.enqueue(site(n)));
  await new Promise((r) => setTimeout(r, 10));
  assert.equal(running, 2, 'two at a time');
  // 2 running + 3 waiting; the sixth was refused
  assert.deepEqual(results, ['queued', 'queued', 'queued', 'queued', 'queued', 'full']);
  while (release.length || running) {
    release.splice(0).forEach((r) => r());
    await new Promise((r) => setTimeout(r, 5));
  }
  await queue.onIdle();
  assert.equal(peak, 2);
  assert.equal(queue.snapshot().dropped, 1);
});

test('a disabled queue accepts nothing', async () => {
  const { queue, calls } = harness({ enabled: false });
  assert.equal(queue.enqueue(site(1)), 'disabled');
  await queue.onIdle();
  assert.equal(calls.crawl.length, 0);
});
