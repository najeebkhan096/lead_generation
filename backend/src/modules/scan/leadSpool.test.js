import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createLeadSpool } from './leadSpool.js';

const lead = (n) => ({ business: `Business ${n}`, phone: `+1415555${String(n).padStart(4, '0')}`, badReview: { text: `review ${n}` } });

async function collect(iterable) {
  const out = [];
  for await (const item of iterable) out.push(item);
  return out;
}

test('leads come back per state, in the order they were added, and are counted', async () => {
  const spool = createLeadSpool({ dir: null });
  await spool.append('Car Wash', 'Texas', [lead(1), lead(2)]);
  await spool.append('Car Wash', 'Texas', [lead(3)]);
  await spool.append('Car Wash', 'Ohio', [lead(4)]);

  assert.equal(spool.count('Car Wash', 'Texas'), 3);
  assert.equal(spool.count('Car Wash', 'Ohio'), 1);
  assert.equal(spool.count('Car Wash', 'Maine'), 0);
  assert.deepEqual((await collect(spool.read('Car Wash', 'Texas'))).map((l) => l.business), ['Business 1', 'Business 2', 'Business 3']);
});

test('on disk, leads survive a round trip and parallel appends never tear a line', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'spool-test-'));
  const spool = createLeadSpool({ dir: path.join(dir, 'job') });
  await Promise.all(Array.from({ length: 50 }, (_, i) => spool.append('Car Wash', 'Texas', [lead(i * 3), lead(i * 3 + 1), lead(i * 3 + 2)])));

  const back = await collect(spool.read('Car Wash', 'Texas'));
  assert.equal(back.length, 150);
  assert.equal(new Set(back.map((l) => l.business)).size, 150, 'every lead is intact and unique');
  assert.equal(back[0].badReview.text, back.find((l) => l.business === back[0].business).badReview.text);

  await spool.remove();
  assert.equal(fs.existsSync(path.join(dir, 'job')), false, 'the spool is deleted with the scan');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('a state with nothing appended reads back empty, on disk too', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'spool-test-'));
  const spool = createLeadSpool({ dir: path.join(dir, 'job') });
  assert.deepEqual(await collect(spool.read('Car Wash', 'Texas')), []);
  await spool.remove();
  fs.rmSync(dir, { recursive: true, force: true });
});
