import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';

const COLLECTION = 'sales';

// Deal-stage progression — separate from either payment status below.
export const LEAD_STATUSES = ['new', 'in_progress', 'completed', 'cancelled'];
// Has the client paid what they were charged (in USD).
export const CLIENT_PAYMENT_STATUSES = ['pending', 'paid', 'stuck', 'received', 'in_process'];
// Has the employee/salesman been paid their cut (in PKR, separate from the
// client's USD payment — this business charges clients in USD but pays
// local staff and covers local costs in PKR).
export const EMPLOYEE_PAYMENT_STATUSES = ['pending', 'paid'];

function computeProfit({ clientAmountReceived, removalCost, employeePaymentAmount }) {
  return (clientAmountReceived || 0) - (removalCost || 0) - (employeePaymentAmount || 0);
}

function docToSale(doc) {
  const data = doc.data();
  const clientAmountReceived = Number(data.clientAmountReceived) || 0;
  const removalCost = Number(data.removalCost) || 0;
  const employeePaymentAmount = Number(data.employeePaymentAmount) || 0;
  return {
    id: doc.id,
    businessName: data.businessName || '',
    reviewLink: data.reviewLink || null,
    salesmanId: data.salesmanId || null,
    salesmanName: data.salesmanName || null,
    leadStatus: LEAD_STATUSES.includes(data.leadStatus) ? data.leadStatus : 'new',
    priceChargedToClient: Number(data.priceChargedToClient) || 0,
    clientPaymentStatus: CLIENT_PAYMENT_STATUSES.includes(data.clientPaymentStatus)
      ? data.clientPaymentStatus
      : 'pending',
    clientPaymentMethod: data.clientPaymentMethod || null,
    employeePaymentAmount,
    employeePaymentStatus: EMPLOYEE_PAYMENT_STATUSES.includes(data.employeePaymentStatus)
      ? data.employeePaymentStatus
      : 'pending',
    clientAmountReceived,
    removalCost,
    profit: computeProfit({ clientAmountReceived, removalCost, employeePaymentAmount }),
    createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
  };
}

function sanitizePayload(input) {
  const payload = {};
  if (input.businessName !== undefined) payload.businessName = String(input.businessName).trim();
  if (input.reviewLink !== undefined) payload.reviewLink = input.reviewLink ? String(input.reviewLink).trim() : null;
  if (input.salesmanId !== undefined) payload.salesmanId = input.salesmanId || null;
  if (input.salesmanName !== undefined) payload.salesmanName = input.salesmanName ? String(input.salesmanName).trim() : null;
  if (input.leadStatus !== undefined) {
    if (!LEAD_STATUSES.includes(input.leadStatus)) {
      const err = new Error(`leadStatus must be one of: ${LEAD_STATUSES.join(', ')}`);
      err.status = 400;
      throw err;
    }
    payload.leadStatus = input.leadStatus;
  }
  if (input.priceChargedToClient !== undefined) payload.priceChargedToClient = Number(input.priceChargedToClient) || 0;
  if (input.clientPaymentStatus !== undefined) {
    if (!CLIENT_PAYMENT_STATUSES.includes(input.clientPaymentStatus)) {
      const err = new Error(`clientPaymentStatus must be one of: ${CLIENT_PAYMENT_STATUSES.join(', ')}`);
      err.status = 400;
      throw err;
    }
    payload.clientPaymentStatus = input.clientPaymentStatus;
  }
  if (input.clientPaymentMethod !== undefined) {
    payload.clientPaymentMethod = input.clientPaymentMethod ? String(input.clientPaymentMethod).trim() : null;
  }
  if (input.employeePaymentAmount !== undefined) payload.employeePaymentAmount = Number(input.employeePaymentAmount) || 0;
  if (input.employeePaymentStatus !== undefined) {
    if (!EMPLOYEE_PAYMENT_STATUSES.includes(input.employeePaymentStatus)) {
      const err = new Error(`employeePaymentStatus must be one of: ${EMPLOYEE_PAYMENT_STATUSES.join(', ')}`);
      err.status = 400;
      throw err;
    }
    payload.employeePaymentStatus = input.employeePaymentStatus;
  }
  if (input.clientAmountReceived !== undefined) payload.clientAmountReceived = Number(input.clientAmountReceived) || 0;
  if (input.removalCost !== undefined) payload.removalCost = Number(input.removalCost) || 0;
  return payload;
}

export async function createSale(input) {
  if (!input.businessName || !String(input.businessName).trim()) {
    const err = new Error('businessName is required');
    err.status = 400;
    throw err;
  }
  const db = getFirestore();
  const payload = sanitizePayload(input);
  const ref = db.collection(COLLECTION).doc();
  await ref.set({
    businessName: payload.businessName,
    reviewLink: payload.reviewLink ?? null,
    salesmanId: payload.salesmanId ?? null,
    salesmanName: payload.salesmanName ?? null,
    leadStatus: payload.leadStatus ?? 'new',
    priceChargedToClient: payload.priceChargedToClient ?? 0,
    clientPaymentStatus: payload.clientPaymentStatus ?? 'pending',
    clientPaymentMethod: payload.clientPaymentMethod ?? null,
    employeePaymentAmount: payload.employeePaymentAmount ?? 0,
    employeePaymentStatus: payload.employeePaymentStatus ?? 'pending',
    clientAmountReceived: payload.clientAmountReceived ?? 0,
    removalCost: payload.removalCost ?? 0,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return docToSale(await ref.get());
}

export async function listSales({ salesmanId, leadStatus } = {}) {
  const db = getFirestore();
  let query = db.collection(COLLECTION);
  if (salesmanId) query = query.where('salesmanId', '==', salesmanId);
  if (leadStatus) query = query.where('leadStatus', '==', leadStatus);
  const snap = await query.get();
  const sales = snap.docs.map(docToSale);
  sales.sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
  return sales;
}

export async function updateSale(id, input) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) return null;
  const payload = sanitizePayload(input);
  await ref.update({ ...payload, updatedAt: FieldValue.serverTimestamp() });
  return docToSale(await ref.get());
}

/**
 * Aggregate stats for the sales dashboard — computed in memory from
 * [listSales] rather than a separate rollup collection; sales volume for
 * an internal tool like this stays small enough that reading every doc on
 * each dashboard load is simpler and cheap enough to not need caching.
 *
 * Two currencies flow through here and are deliberately never summed
 * together: `priceChargedToClient` (what clients are billed) is USD;
 * everything else — employee payout, client amount actually received,
 * removal cost, profit — is PKR (local operations currency).
 */
export async function getSalesStats({ salesmanId } = {}) {
  const sales = await listSales({ salesmanId });

  const totals = {
    totalSales: sales.length,
    totalRevenueUsd: 0,
    totalEmployeePayoutPkr: 0,
    totalClientReceivedPkr: 0,
    totalRemovalCostPkr: 0,
    totalProfitPkr: 0,
  };

  const byLeadStatus = Object.fromEntries(LEAD_STATUSES.map((s) => [s, { count: 0 }]));
  const byClientPaymentStatus = Object.fromEntries(CLIENT_PAYMENT_STATUSES.map((s) => [s, { count: 0 }]));
  const byEmployeePaymentStatus = Object.fromEntries(EMPLOYEE_PAYMENT_STATUSES.map((s) => [s, { count: 0 }]));
  const bySalesmanMap = new Map();

  for (const sale of sales) {
    totals.totalRevenueUsd += sale.priceChargedToClient;
    totals.totalEmployeePayoutPkr += sale.employeePaymentAmount;
    totals.totalClientReceivedPkr += sale.clientAmountReceived;
    totals.totalRemovalCostPkr += sale.removalCost;
    totals.totalProfitPkr += sale.profit;

    byLeadStatus[sale.leadStatus].count += 1;
    byClientPaymentStatus[sale.clientPaymentStatus].count += 1;
    byEmployeePaymentStatus[sale.employeePaymentStatus].count += 1;

    const key = sale.salesmanId || 'unassigned';
    if (!bySalesmanMap.has(key)) {
      bySalesmanMap.set(key, {
        salesmanId: sale.salesmanId,
        salesmanName: sale.salesmanName || 'Unassigned',
        count: 0,
        revenueUsd: 0,
        employeePayoutPkr: 0,
        profitPkr: 0,
        completedCount: 0,
      });
    }
    const entry = bySalesmanMap.get(key);
    entry.count += 1;
    entry.revenueUsd += sale.priceChargedToClient;
    entry.employeePayoutPkr += sale.employeePaymentAmount;
    entry.profitPkr += sale.profit;
    if (sale.leadStatus === 'completed') entry.completedCount += 1;
  }

  const bySalesman = [...bySalesmanMap.values()].sort((a, b) => b.revenueUsd - a.revenueUsd);

  return { ...totals, byLeadStatus, byClientPaymentStatus, byEmployeePaymentStatus, bySalesman };
}

export async function deleteSale(id) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) return false;
  await ref.delete();
  return true;
}
