import { scanClientReviews } from './clientReviewScanner.js';
import { launchBrowser, checkBrowserSignedIn } from '../../scraper/googleMapsScraper.js';
import { listClients, createClient, updateClient, deleteClient } from './clientStore.js';

const fail = (res, err, fallback) => res.status(err.status || 500).json({ error: err.message || fallback });

export async function getClients(req, res) {
  try {
    return res.json({ clients: await listClients() });
  } catch (err) {
    return fail(res, err, 'Failed to load clients');
  }
}

export async function addClient(req, res) {
  try {
    return res.json({ client: await createClient(req.body || {}) });
  } catch (err) {
    return fail(res, err, 'Failed to create client');
  }
}

export async function editClient(req, res) {
  try {
    const client = await updateClient(req.params.id, req.body || {});
    if (!client) return res.status(404).json({ error: 'Client not found' });
    return res.json({ client });
  } catch (err) {
    return fail(res, err, 'Failed to update client');
  }
}

export async function removeClient(req, res) {
  try {
    const ok = await deleteClient(req.params.id);
    if (!ok) return res.status(404).json({ error: 'Client not found' });
    return res.json({ success: true });
  } catch (err) {
    return fail(res, err, 'Failed to delete client');
  }
}

let scanning = false;

/** POST /api/clients/scan-reviews  { dateRange? } — days, default 28. */
export async function scanReviews(req, res) {
  if (scanning) return res.status(409).json({ error: 'A client review scan is already running' });
  scanning = true;
  try {
    // Reading reviews completely needs a signed-in Google account; without it
    // every client would come back "could not be fully checked".
    const probe = await launchBrowser();
    let session;
    try {
      session = await checkBrowserSignedIn(probe);
    } finally {
      await probe.close().catch(() => {});
    }
    if (session.status === 'anonymous' || session.status === 'signed_out') {
      return res.status(409).json({
        code: 'GOOGLE_SIGN_IN_REQUIRED',
        error: 'Sign in to Google first (Sign in to Google on the Excel Scan page, or `npm run maps:login`): without it Google hides most reviews and 1-star reviews would be missed.',
      });
    }
    const { dateRange } = req.body || {};
    const days = Number(dateRange);
    const results = await scanClientReviews({
      dateRange: Number.isFinite(days) && days > 0 ? String(Math.min(Math.floor(days), 365)) : '28',
    });
    return res.json({ results, scannedAt: new Date().toISOString() });
  } catch (err) {
    return fail(res, err, 'Client review scan failed');
  } finally {
    scanning = false;
  }
}
