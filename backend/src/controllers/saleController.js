import {
  createSale,
  listSales,
  updateSale,
  deleteSale,
  getSalesStats,
} from '../services/saleStore.js';
import { scanSaleReviews } from '../services/salesReviewScanner.js';

export async function addSale(req, res) {
  try {
    const sale = await createSale(req.body || {});
    return res.json({ sale });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to create sale' });
  }
}

export async function getSales(req, res) {
  try {
    const { salesmanId, leadStatus } = req.query || {};
    const sales = await listSales({
      salesmanId: salesmanId ? String(salesmanId) : undefined,
      leadStatus: leadStatus ? String(leadStatus) : undefined,
    });
    return res.json({ sales });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load sales' });
  }
}

export async function editSale(req, res) {
  try {
    const sale = await updateSale(req.params.id, req.body || {});
    if (!sale) return res.status(404).json({ error: 'Sale not found' });
    return res.json({ sale });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to update sale' });
  }
}

export async function removeSale(req, res) {
  try {
    const ok = await deleteSale(req.params.id);
    if (!ok) return res.status(404).json({ error: 'Sale not found' });
    return res.json({ success: true });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to delete sale' });
  }
}

export async function getStats(req, res) {
  try {
    const { salesmanId } = req.query || {};
    const stats = await getSalesStats({ salesmanId: salesmanId ? String(salesmanId) : undefined });
    return res.json({ stats });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Failed to load sales stats' });
  }
}

let scanningReviews = false;

export async function scanReviews(req, res) {
  if (scanningReviews) {
    return res.status(409).json({ error: 'A sales review scan is already running' });
  }
  scanningReviews = true;
  try {
    const { dateRange, salesmanId } = req.body || {};
    const results = await scanSaleReviews({
      dateRange: dateRange ? String(dateRange) : '30',
      salesmanId: salesmanId ? String(salesmanId) : undefined,
    });
    return res.json({ results, scannedAt: new Date().toISOString() });
  } catch (err) {
    return res.status(err.status || 500).json({ error: err.message || 'Sales review scan failed' });
  } finally {
    scanningReviews = false;
  }
}
