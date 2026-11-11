/**
 * One-time tagging of the already-validated no-website leads, so the phone app
 * can list exactly the no-website scans' leads (see `tagVerifiedNoWebsiteLeads`
 * in src/modules/leads/websiteLeadStore.js for the rule).
 *
 * Only adds `scanModes: ['no_website']` to validated leads that a no-website
 * scan found; it changes nothing else and removes nothing.
 *
 * Usage:
 *   node scripts/tagNoWebsiteLeads.js            # dry run: counts, no writes
 *   node scripts/tagNoWebsiteLeads.js --apply    # writes the tags
 */

import { initFirebase } from '../src/firebase/admin.js';
import { tagVerifiedNoWebsiteLeads } from '../src/modules/leads/websiteLeadStore.js';

initFirebase();

const apply = process.argv.includes('--apply');
const result = await tagVerifiedNoWebsiteLeads({ apply });

console.log(`${apply ? 'APPLIED' : 'DRY RUN (no writes)'}`);
console.log(`Validated no-website leads on file: ${result.validated}`);
console.log(`${apply ? 'Tagged' : 'Would tag'} as no-website-scan leads: ${result.tagged}`);
const leftTotal = result.left.reduce((sum, r) => sum + r.count, 0);
console.log(`Left untagged (1-star scan side-finds, hidden from the phone's No Website tab): ${leftTotal}`);
for (const row of result.left.slice(0, 25)) console.log(`  ${String(row.count).padStart(5)}  ${row.category}`);
process.exit(0);
