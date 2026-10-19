import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { leadsToXlsxBuffer, writeLeadsXlsxFile, xlsxBufferToJson } from './exportService.js';

const lead = (n) => ({
  business: `Biz ${n} & Co`, category: 'automotive', location: 'Texas', address: `${n} Main St`,
  phone: `+1214555${1000 + n}`, website: `https://x${n}.example`, mapsUrl: `https://maps/${n}`,
  rating: 3.5, totalReviews: 40, badReview: { stars: 1, text: `bad ${n}`, date: '1 week ago', reviewer: `R${n}` },
  status: 'lead',
});

async function* asyncOf(list) {
  yield* list;
}

test('the streamed workbook has the same sheets and rows as the one built in memory', async () => {
  const sheets = [{ name: 'Texas', leads: [lead(1), lead(2)] }, { name: 'Ohio', leads: [lead(3)] }];
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'xlsx-test-')), 'streamed.xlsx');

  await writeLeadsXlsxFile(file, sheets.map((s) => ({ name: s.name, leads: asyncOf(s.leads) })));
  const streamed = await xlsxBufferToJson(fs.readFileSync(file));
  const buffered = await xlsxBufferToJson(await leadsToXlsxBuffer(sheets));

  assert.deepEqual(streamed, buffered);
  fs.rmSync(path.dirname(file), { recursive: true, force: true });
});

test('an empty scan still writes a readable workbook', async () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'xlsx-test-')), 'empty.xlsx');
  await writeLeadsXlsxFile(file, []);
  const back = await xlsxBufferToJson(fs.readFileSync(file));
  assert.equal(back.length, 1);
  assert.equal(back[0].rows.length, 0);
  fs.rmSync(path.dirname(file), { recursive: true, force: true });
});
