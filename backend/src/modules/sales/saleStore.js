import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../../firebase/admin.js';

const COLLECTION = 'sales';

// Deal-stage progression — separate from either payment status below.
//   new          deal locked: the salesman closed it with the client
//   in_progress  removal: our team is doing the work
//   payment      removal done, waiting for the client to pay
//   completed    the client has paid
// (Stored values for the first two predate the process naming; kept so
// existing documents and older clients keep working.)
export const LEAD_STATUSES = ['new', 'in_progress', 'payment', 'completed', 'cancelled'];
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
    clientId: data.clientId || null,
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
    // True when this sale's payment figures predate the "fresh start": the
    // sale and its client stay, but the money is excluded from payout,
    // billing and profit totals. See archivePayments().
    paymentsArchived: data.paymentsArchived === true,
    paymentsArchivedAt: data.paymentsArchivedAt?.toDate?.()?.toISOString() || null,
    createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() || null,
    lastReviewScannedAt: data.lastReviewScannedAt?.toDate?.()?.toISOString() || null,
    lastOneStarCount: Number(data.lastOneStarCount) || 0,
    lastReviewScanError: data.lastReviewScanError || null,
    lastRating: data.lastRating ?? null,
    lastTotalReviews: data.lastTotalReviews ?? null,
  };
}

function sanitizePayload(input) {
  const payload = {};
  if (input.businessName !== undefined) payload.businessName = String(input.businessName).trim();
  if (input.clientId !== undefined) payload.clientId = input.clientId || null;
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
  if (input.paymentsArchived !== undefined) {
    payload.paymentsArchived = input.paymentsArchived === true;
    payload.paymentsArchivedAt = payload.paymentsArchived ? FieldValue.serverTimestamp() : null;
  }
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
    clientId: payload.clientId ?? null,
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
    paymentsArchived: false,
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
  return computeSalesStats(await listSales({ salesmanId }));
}

/**
 * Pure aggregation behind [getSalesStats]. Sales whose payments were
 * archived still count as orders (totalSales, byLeadStatus, per-salesman
 * counts) but contribute nothing to any money total.
 */
export function computeSalesStats(sales) {
  const totals = {
    totalSales: sales.length,
    archivedSales: sales.filter((s) => s.paymentsArchived).length,
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
    const counted = !sale.paymentsArchived;
    if (counted) {
      totals.totalRevenueUsd += sale.priceChargedToClient;
      totals.totalEmployeePayoutPkr += sale.employeePaymentAmount;
      totals.totalClientReceivedPkr += sale.clientAmountReceived;
      totals.totalRemovalCostPkr += sale.removalCost;
      totals.totalProfitPkr += sale.profit;
      byClientPaymentStatus[sale.clientPaymentStatus].count += 1;
      byEmployeePaymentStatus[sale.employeePaymentStatus].count += 1;
    }

    byLeadStatus[sale.leadStatus].count += 1;

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
    if (counted) {
      entry.revenueUsd += sale.priceChargedToClient;
      entry.employeePayoutPkr += sale.employeePaymentAmount;
      entry.profitPkr += sale.profit;
    }
    if (sale.leadStatus === 'completed') entry.completedCount += 1;
  }

  const bySalesman = [...bySalesmanMap.values()].sort((a, b) => b.revenueUsd - a.revenueUsd);

  return { ...totals, byLeadStatus, byClientPaymentStatus, byEmployeePaymentStatus, bySalesman };
}

/**
 * Chooses which sales a fresh-start archive (or its undo) touches.
 *
 * - archive: sales created before [before] that are not archived yet.
 *   Sales with no createdAt predate timestamps and count as old.
 * - restore: every archived sale (optionally only those created before
 *   [before]).
 */
export function selectForArchive(sales, { before, restore = false } = {}) {
  const cutoff = before ? new Date(before).getTime() : null;
  const isOld = (s) => {
    if (cutoff === null) return true;
    if (!s.createdAt) return true;
    return new Date(s.createdAt).getTime() < cutoff;
  };
  return sales.filter((s) => (restore ? s.paymentsArchived && isOld(s) : !s.paymentsArchived && isOld(s)));
}

/**
 * "Start fresh from today": flags older sales so their payment figures stop
 * counting. Nothing is deleted or edited — the sale, its client and every
 * amount stay on the document, and `restore: true` undoes it.
 *
 * Defaults to a dry run; pass `apply: true` to write.
 */
export async function archivePayments({ before, restore = false, apply = false } = {}) {
  if (before && Number.isNaN(new Date(before).getTime())) {
    const err = new Error('before must be a valid date');
    err.status = 400;
    throw err;
  }
  const sales = await listSales();
  const targets = selectForArchive(sales, { before, restore });
  const summary = {
    mode: restore ? 'restore' : 'archive',
    applied: apply,
    before: before || null,
    totalSales: sales.length,
    matched: targets.length,
    alreadyArchived: sales.filter((s) => s.paymentsArchived).length,
    updated: 0,
  };
  if (!apply || targets.length === 0) return summary;

  const db = getFirestore();
  const BATCH = 400;
  for (let i = 0; i < targets.length; i += BATCH) {
    const batch = db.batch();
    for (const sale of targets.slice(i, i + BATCH)) {
      // updatedAt is left alone so lists ordered by it do not reshuffle.
      batch.update(db.collection(COLLECTION).doc(sale.id), {
        paymentsArchived: !restore,
        paymentsArchivedAt: restore ? null : FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    summary.updated += Math.min(BATCH, targets.length - i);
  }
  return summary;
}

export async function deleteSale(id) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) return false;
  await ref.delete();
  return true;
}

/** Persists the last 1-star review scan onto the sale — separate from
 * form edits so a scan never overwrites billing/status fields. */
export async function recordSaleReviewScan(id, { rating, totalReviews, newReviewCount, error }) {
  const db = getFirestore();
  await db.collection(COLLECTION).doc(id).update({
    lastReviewScannedAt: FieldValue.serverTimestamp(),
    lastRating: rating ?? null,
    lastTotalReviews: totalReviews ?? null,
    lastOneStarCount: newReviewCount ?? 0,
    lastReviewScanError: error || null,
    updatedAt: FieldValue.serverTimestamp(),
  });
}
