import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import searchRoutes from './routes/searchRoutes.js';
import multiSearchRoutes from './routes/multiSearchRoutes.js';
import exportRoutes from './routes/exportRoutes.js';
import dbRoutes from './routes/dbRoutes.js';
import whatsappRoutes from './routes/whatsappRoutes.js';
import whatsappWebRoutes from './routes/whatsappWebRoutes.js';
import watchlistRoutes from './routes/watchlistRoutes.js';
import excelArchiveRoutes from './routes/excelArchiveRoutes.js';
import whatsappValidatedRoutes from './routes/whatsappValidatedRoutes.js';
import userRoutes from './routes/userRoutes.js';
import saleRoutes from './routes/saleRoutes.js';
import stateCityScanRoutes from './routes/stateCityScanRoutes.js';
import outreachRoutes from './routes/outreachRoutes.js';
import { initFirebase, getFirebaseStatus } from './firebase/admin.js';
import { startQueueWorker } from './services/outreach/outreachOrchestrator.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3001;

// Flutter web build (copied to backend/public in production / Docker)
const webRoot = path.resolve(__dirname, '../public');

// Chrome Private Network Access: the Firebase-hosted HTTPS origin talking
// to localhost:3001 is a public→private request and gets blocked unless
// this header is on the CORS preflight. Must run before `cors()`.
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Private-Network', 'true');
  next();
});
app.use(cors({
  origin: '*',
  // PATCH was missing here — every PATCH route (e.g. sale edits, lead
  // WhatsApp-status updates) failed its CORS preflight and surfaced to
  // the browser as a bare "Failed to fetch", indistinguishable from the
  // backend being down.
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '16mb' }));

initFirebase();

app.get('/api/health', (_req, res) => {
  const fb = getFirebaseStatus();
  res.json({
    ok: true,
    service: 'lead-generation-backend',
    storage: 'firebase',
    firebase: fb,
    note: 'Session search results are in-memory until you Save to Firebase.',
  });
});

app.use('/api/search', searchRoutes);
app.use('/api/search/multi', multiSearchRoutes);
app.use('/api/export', exportRoutes);
app.use('/api/db', dbRoutes);
app.use('/api/whatsapp', whatsappRoutes);
app.use('/api/whatsapp-web', whatsappWebRoutes);
app.use('/api/watchlist', watchlistRoutes);
app.use('/api/excel-scans', excelArchiveRoutes);
app.use('/api/whatsapp-validated-scans', whatsappValidatedRoutes);
app.use('/api/users', userRoutes);
app.use('/api/sales', saleRoutes);
app.use('/api/state-scan', stateCityScanRoutes);
app.use('/api/outreach', outreachRoutes);

if (fs.existsSync(path.join(webRoot, 'index.html'))) {
  app.use(express.static(webRoot, { index: false }));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api')) return next();
    res.sendFile(path.join(webRoot, 'index.html'));
  });
}

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: err.message || 'Internal error' });
});

app.listen(PORT, '0.0.0.0', () => {
  const fb = getFirebaseStatus();
  console.log(`Lead generation API running on http://0.0.0.0:${PORT}`);
  console.log(
    fb.configured
      ? 'Storage: Firebase Firestore (Save to Firebase after search)'
      : `Storage: Firebase not configured — ${fb.error || 'add service account JSON'}`
  );
  if (fs.existsSync(path.join(webRoot, 'index.html'))) {
    console.log(`Serving Flutter web from ${webRoot}`);
  }
  try {
    if (getFirebaseStatus().configured) startQueueWorker();
  } catch (err) {
    console.warn('Outreach queue worker not started:', err.message || err);
  }
});
