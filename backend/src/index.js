import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import searchRoutes from './routes/searchRoutes.js';
import exportRoutes from './routes/exportRoutes.js';
import dbRoutes from './routes/dbRoutes.js';
import { initFirebase, getFirebaseStatus } from './firebase/admin.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3001;

// Flutter web build (copied to backend/public in production / Docker)
const webRoot = path.resolve(__dirname, '../public');

app.use(cors());
app.use(express.json({ limit: '2mb' }));

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
app.use('/api/export', exportRoutes);
app.use('/api/db', dbRoutes);

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
});
