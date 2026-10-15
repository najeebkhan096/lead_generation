/**
 * Moves the business name + Google Maps link of every existing sale into the
 * `clients` collection, and (separately, on request) removes the old sales
 * records.
 *
 *   node scripts/migrateClients.js                          # dry run: shows the plan
 *   node scripts/migrateClients.js --apply                  # backup sales, then create/refresh clients
 *   node scripts/migrateClients.js --apply --delete-sales   # ...and then delete the sales documents
 *
 * Safety:
 * - Always writes a full JSON backup of `sales` to backend/data/backups
 *   BEFORE anything else when --apply is passed.
 * - Client creation never overwrites a link that is already saved.
 * - Sales are deleted only with the explicit --delete-sales flag, and only
 *   after the backup and the clients were written.
 *
 * NOTE: uses whatever Firebase credentials this machine's backend uses —
 * i.e. production, if backend/firebase-service-account.json is configured.
 */

import fs from 'fs';
import path from 'path';
import { FieldValue } from 'firebase-admin/firestore';
import { initFirebase, getFirestore } from '../src/firebase/admin.js';
import { listSales } from '../src/modules/sales/saleStore.js';
import { planClients } from '../src/modules/clients/clientMigration.js';
import { clientDocId } from '../src/modules/clients/clientStore.js';
import { BACKEND_ROOT } from '../src/lib/paths.js';

const apply = process.argv.includes('--apply');
const deleteSales = process.argv.includes('--delete-sales');

if (deleteSales && !apply) {
  console.error('--delete-sales needs --apply (it only runs after the backup and clients are written).');
  process.exit(1);
}

initFirebase();
const db = getFirestore();
const sales = await listSales();
const plan = planClients(sales);

console.log(`${sales.length} sales → ${plan.length} clients\n`);
for (const c of plan) {
  const link = c.mapsUrl ? c.mapsUrl : '— no valid Google Maps link —';
  console.log(`• ${c.businessName}  (${c.orders} ${c.orders === 1 ? 'order' : 'orders'})\n    ${link}`);
  for (const alt of c.alternateUrls) console.log(`    also seen: ${alt}`);
  for (const bad of c.rejectedLinks) console.log(`    ignored (not a Google link): ${JSON.stringify(bad)}`);
}
const missing = plan.filter((c) => !c.mapsUrl).length;
console.log(`\n${plan.length - missing} with a link, ${missing} still need one.`);

if (!apply) {
  console.log('\nDry run only. Re-run with --apply to back up the sales and create the clients.');
  process.exit(0);
}

// 1. Backup — everything on the sales documents, as stored.
const backupDir = path.join(BACKEND_ROOT, 'data', 'backups');
fs.mkdirSync(backupDir, { recursive: true });
const raw = await db.collection('sales').get();
const backupFile = path.join(backupDir, `sales-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
fs.writeFileSync(
  backupFile,
  JSON.stringify(raw.docs.map((d) => ({ id: d.id, data: d.data() })), null, 2),
);
console.log(`\nBackup written: ${backupFile} (${raw.size} sales)`);

// 2. Clients — never overwrite a link that is already saved.
let created = 0;
let kept = 0;
for (const c of plan) {
  const ref = db.collection('clients').doc(clientDocId(c.businessName));
  const existing = await ref.get();
  if (existing.exists) {
    const patch = {};
    if (!existing.data().mapsUrl && c.mapsUrl) patch.mapsUrl = c.mapsUrl;
    if (Object.keys(patch).length) await ref.update({ ...patch, updatedAt: FieldValue.serverTimestamp() });
    kept += 1;
  } else {
    await ref.set({
      businessName: c.businessName,
      nameKey: c.nameKey,
      mapsUrl: c.mapsUrl,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    created += 1;
  }
}
console.log(`Clients: ${created} created, ${kept} already existed.`);

// 3. Old sales records — only when explicitly asked.
if (deleteSales) {
  let deleted = 0;
  for (let i = 0; i < raw.docs.length; i += 400) {
    const batch = db.batch();
    for (const d of raw.docs.slice(i, i + 400)) batch.delete(d.ref);
    await batch.commit();
    deleted += Math.min(400, raw.docs.length - i);
  }
  console.log(`Deleted ${deleted} sales documents (backup above).`);
} else {
  console.log('Sales left untouched. Add --delete-sales to remove the old records.');
}
process.exit(0);
