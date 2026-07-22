import express from 'express';
import cors from 'cors';
import searchRoutes from './routes/searchRoutes.js';
import exportRoutes from './routes/exportRoutes.js';

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'lead-generation-backend',
    storage: 'in-memory',
    note: 'No database. Session data is lost on restart.',
  });
});

app.use('/api/search', searchRoutes);
app.use('/api/export', exportRoutes);

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: err.message || 'Internal error' });
});

app.listen(PORT, () => {
  console.log(`Lead generation API running on http://localhost:${PORT}`);
  console.log('Storage: in-memory only (no database)');
});
