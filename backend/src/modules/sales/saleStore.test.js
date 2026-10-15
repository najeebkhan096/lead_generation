import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeSalesStats, selectForArchive } from './saleStore.js';

const sale = (over) => ({
  id: 'x',
  salesmanId: 'u1',
  salesmanName: 'Ali',
  leadStatus: 'completed',
  priceChargedToClient: 0,
  clientPaymentStatus: 'pending',
  employeePaymentAmount: 0,
  employeePaymentStatus: 'pending',
  clientAmountReceived: 0,
  removalCost: 0,
  profit: 0,
  paymentsArchived: false,
  createdAt: '2026-10-20T08:00:00.000Z',
  ...over,
});

test('archived sales still count as orders but add no money', () => {
  const stats = computeSalesStats([
    sale({ id: '1', paymentsArchived: true, priceChargedToClient: 100, employeePaymentAmount: 500, clientAmountReceived: 9000, profit: 8500, clientPaymentStatus: 'paid', employeePaymentStatus: 'paid' }),
    sale({ id: '2', priceChargedToClient: 40, employeePaymentAmount: 200, clientAmountReceived: 3000, removalCost: 100, profit: 2700 }),
  ]);
  assert.equal(stats.totalSales, 2);
  assert.equal(stats.archivedSales, 1);
  assert.equal(stats.byLeadStatus.completed.count, 2);
  assert.equal(stats.totalRevenueUsd, 40);
  assert.equal(stats.totalEmployeePayoutPkr, 200);
  assert.equal(stats.totalClientReceivedPkr, 3000);
  assert.equal(stats.totalProfitPkr, 2700);
  assert.equal(stats.byClientPaymentStatus.paid.count, 0);
  assert.equal(stats.byEmployeePaymentStatus.pending.count, 1);
  const ali = stats.bySalesman[0];
  assert.equal(ali.count, 2);
  assert.equal(ali.completedCount, 2);
  assert.equal(ali.profitPkr, 2700);
});

test('archive picks sales created before the cutoff that are not archived yet', () => {
  const sales = [
    sale({ id: 'old', createdAt: '2026-10-01T00:00:00.000Z' }),
    sale({ id: 'today', createdAt: '2026-10-16T09:00:00.000Z' }),
    sale({ id: 'done', createdAt: '2026-09-01T00:00:00.000Z', paymentsArchived: true }),
    sale({ id: 'undated', createdAt: null }),
  ];
  const ids = selectForArchive(sales, { before: '2026-10-16T00:00:00.000Z' }).map((s) => s.id);
  assert.deepEqual(ids.sort(), ['old', 'undated']);
});

test('restore picks only archived sales', () => {
  const sales = [
    sale({ id: 'a', paymentsArchived: true }),
    sale({ id: 'b' }),
  ];
  assert.deepEqual(selectForArchive(sales, { restore: true }).map((s) => s.id), ['a']);
});
