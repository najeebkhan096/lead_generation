import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSalesmanStats, clampDays, dayKey, recentDayKeys } from './salesmanStats.js';

const NOW = new Date('2026-10-18T10:00:00Z'); // 14:00 on the 18th in Dubai

const users = [
  { id: 'ali', name: 'Ali', role: 'salesman', approved: true, dailyLeadLimit: 2 },
  { id: 'bo', name: 'Bo', role: 'salesman', approved: true, dailyLeadLimit: 10 },
];

const contact = (contactedBy, iso) => ({ sourceType: 'review', status: 'contacted', contactedBy, contactedAt: new Date(iso) });

const leads = [
  contact('ali', '2026-10-18T06:00:00Z'), // today
  contact('ali', '2026-10-18T09:00:00Z'), // today
  contact('ali', '2026-10-17T10:00:00Z'), // yesterday
  contact('ali', '2026-10-10T10:00:00Z'), // eight days ago: outside the last 7
  contact('bo', '2026-10-18T07:00:00Z'), // today
  contact('gone', '2026-10-18T08:00:00Z'), // a user no longer in the list
  { sourceType: 'review', status: 'lead', contactedBy: null, contactedAt: null }, // still New
];

test('a day belongs to the Dubai date it falls on', () => {
  assert.equal(dayKey(new Date('2026-10-18T19:59:00Z')), '2026-10-18');
  assert.equal(dayKey(new Date('2026-10-18T20:00:00Z')), '2026-10-19');
});

test('recentDayKeys lists the days ending today, oldest first', () => {
  assert.deepEqual(recentDayKeys('2026-10-01', 3), ['2026-09-29', '2026-09-30', '2026-10-01']);
});

test('clampDays keeps the range to 1 to 60, defaulting to 14', () => {
  assert.equal(clampDays(undefined), 14);
  assert.equal(clampDays('abc'), 14);
  assert.equal(clampDays('0'), 1);
  assert.equal(clampDays('999'), 60);
  assert.equal(clampDays('7'), 7);
});

test('each salesman gets today, the last 7 days, the total, and their daily chart', () => {
  const stats = buildSalesmanStats({ users, leads, now: NOW, days: 14 });
  const ali = stats.salesmen.find((s) => s.id === 'ali');

  assert.equal(stats.today, '2026-10-18');
  assert.equal(ali.contactedToday, 2);
  assert.equal(ali.contactedLast7, 3); // today's 2 and yesterday's 1
  assert.equal(ali.contactedTotal, 4);
  assert.equal(ali.activeDays, 3);
  assert.equal(ali.averagePerActiveDay, 1.3);
  assert.equal(ali.daily.length, 14);
  assert.deepEqual(ali.daily.at(-1), { day: '2026-10-18', count: 2 });
});

test('the limit shows what is left today, and how many days hit it', () => {
  const stats = buildSalesmanStats({ users, leads, now: NOW, days: 14 });
  const ali = stats.salesmen.find((s) => s.id === 'ali');
  const bo = stats.salesmen.find((s) => s.id === 'bo');

  assert.equal(ali.dailyLeadLimit, 2);
  assert.equal(ali.limitLeftToday, 0);
  assert.equal(ali.daysAtLimit, 1);
  assert.equal(bo.limitLeftToday, 9);
});

test('totals cover every salesman, and leads not yet contacted are counted as New', () => {
  const stats = buildSalesmanStats({ users, leads, now: NOW, days: 14 });

  assert.equal(stats.totals.contactedToday, 3);
  assert.equal(stats.totals.contactedTotal, 6); // includes the contact by a user no longer listed
  assert.equal(stats.totals.activeSalesmen, 2);
  assert.equal(stats.totals.reviewLeads, 7);
  assert.equal(stats.totals.newLeft, 1);
  assert.equal(stats.totals.daily.at(-1).count, 3);
});

test('salesmen with the most contacts are listed first', () => {
  const stats = buildSalesmanStats({ users, leads, now: NOW, days: 14 });
  assert.deepEqual(stats.salesmen.map((s) => s.id), ['ali', 'bo']);
});
