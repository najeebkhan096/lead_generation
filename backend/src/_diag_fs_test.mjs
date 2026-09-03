import { getFirestore } from './firebase/admin.js';
console.log('start', Date.now());
try {
  const db = getFirestore();
  const ref = db.collection('_diag').doc('ping');
  const start = Date.now();
  await Promise.race([
    ref.set({ ts: Date.now() }),
    new Promise((_, rej) => setTimeout(() => rej(new Error('timeout after 10s')), 10000)),
  ]);
  console.log('write ok', Date.now() - start, 'ms');
} catch (err) {
  console.log('ERROR:', err.message);
}
process.exit(0);
