/**
 * "Start fresh from today": stop counting the payment figures of older
 * sales without deleting or changing them.
 *
 * Each matched sale gets `paymentsArchived: true`. The sale and its client
 * stay in the app and keep every amount; the amounts just no longer feed
 * payouts, billing or profit totals. Undo with --restore.
 *
 *   node scripts/archiveSalePayments.js                       # dry run, sales before today
 *   node scripts/archiveSalePayments.js --apply               # write
 *   node scripts/archiveSalePayments.js --before=2026-10-01   # custom cutoff (local midnight)
 *   node scripts/archiveSalePayments.js --restore --apply     # undo
 *
 * NOTE: uses whatever Firebase credentials this machine's backend uses —
 * i.e. production, if backend/firebase-service-account.json is configured.
 */

import { initFirebase } from '../src/firebase/admin.js';
import { archivePayments } from '../src/modules/sales/saleStore.js';

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const restore = args.includes('--restore');
const beforeArg = args.find((a) => a.startsWith('--before='))?.split('=')[1];

function startOfDay(dateString) {
  const d = dateString ? new Date(`${dateString}T00:00:00`) : new Date();
  if (Number.isNaN(d.getTime())) {
    console.error(`Invalid --before date: ${dateString}`);
    process.exit(1);
  }
  d.setHours(0, 0, 0, 0);
  return d;
}

initFirebase();
const before = startOfDay(beforeArg);
const result = await archivePayments({ before: before.toISOString(), restore, apply });

console.log(`${restore ? 'Restore' : 'Archive'} — sales created before ${before.toString()}`);
console.log(JSON.stringify(result, null, 2));
if (!apply) console.log('\nDry run only. Re-run with --apply to write.');
process.exit(0);
