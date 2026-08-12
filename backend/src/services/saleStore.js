import { FieldValue } from 'firebase-admin/firestore';
import { getFirestore } from '../firebase/admin.js';

const COLLECTION = 'sales';

export const SALE_STATUSES = ['order_placed', 'client_paid', 'payment_pending_paypal', 'completed'];

function docToSale(doc) {
  const data = doc.data();
  return {
    id: doc.id,
    businessName: data.businessName || '',
    reviewLink: data.reviewLink || null,
    salesmanId: data.salesmanId || null,
    salesmanName: data.salesmanName || null,
    price: Number(data.price) || 0,
    salesmanPrice: Number(data.salesmanPrice) || 0,
    status: SALE_STATUSES.includes(data.status) ? data.status : 'order_placed',
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
  if (input.price !== undefined) payload.price = Number(input.price) || 0;
  if (input.salesmanPrice !== undefined) payload.salesmanPrice = Number(input.salesmanPrice) || 0;
  if (input.status !== undefined) {
    if (!SALE_STATUSES.includes(input.status)) {
      const err = new Error(`status must be one of: ${SALE_STATUSES.join(', ')}`);
      err.status = 400;
      throw err;
    }
    payload.status = input.status;
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
    reviewLink: payload.reviewLink ?? null,
    salesmanId: payload.salesmanId ?? null,
    salesmanName: payload.salesmanName ?? null,
    price: payload.price ?? 0,
    salesmanPrice: payload.salesmanPrice ?? 0,
    status: payload.status ?? 'order_placed',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return docToSale(await ref.get());
}

export async function listSales({ salesmanId, status } = {}) {
  const db = getFirestore();
  let query = db.collection(COLLECTION);
  if (salesmanId) query = query.where('salesmanId', '==', salesmanId);
  if (status) query = query.where('status', '==', status);
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
 */
export async function getSalesStats({ salesmanId } = {}) {
  const sales = await listSales({ salesmanId });

  const totals = {
    totalSales: sales.length,
    totalRevenue: 0,
    totalSalesmanPayout: 0,
    totalProfit: 0,
  };

  const byStatus = Object.fromEntries(SALE_STATUSES.map((s) => [s, { count: 0, revenue: 0 }]));
  const bySalesmanMap = new Map();

  for (const sale of sales) {
    totals.totalRevenue += sale.price;
    totals.totalSalesmanPayout += sale.salesmanPrice;
    totals.totalProfit += sale.price - sale.salesmanPrice;

    byStatus[sale.status].count += 1;
    byStatus[sale.status].revenue += sale.price;

    const key = sale.salesmanId || 'unassigned';
    if (!bySalesmanMap.has(key)) {
      bySalesmanMap.set(key, {
        salesmanId: sale.salesmanId,
        salesmanName: sale.salesmanName || 'Unassigned',
        count: 0,
        revenue: 0,
        payout: 0,
        profit: 0,
        completedCount: 0,
      });
    }
    const entry = bySalesmanMap.get(key);
    entry.count += 1;
    entry.revenue += sale.price;
    entry.payout += sale.salesmanPrice;
    entry.profit += sale.price - sale.salesmanPrice;
    if (sale.status === 'completed') entry.completedCount += 1;
  }

  const bySalesman = [...bySalesmanMap.values()].sort((a, b) => b.revenue - a.revenue);

  return { ...totals, byStatus, bySalesman };
}

export async function deleteSale(id) {
  const db = getFirestore();
  const ref = db.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) return false;
  await ref.delete();
  return true;
}
