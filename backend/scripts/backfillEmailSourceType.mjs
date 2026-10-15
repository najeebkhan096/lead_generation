/**
 * One-off: gives every `emailLeads` document a `sourceType` (`review` |
 * `website`), which the email validator did not write until now.
 *
 * The signal is recovered from the source collections — a business has the
 * same document id in `leads` (1-star review) and `websiteLeads` (no
 * website) as in `emailLeads`. A document found in both, or in neither, is
 * left alone and reported. Only the one field is written (never `updatedAt`),
 * so ordering and dates do not move.
 *
 *   node scripts/backfillEmailSourceType.mjs            # dry run: report only
 *   node scripts/backfillEmailSourceType.mjs --apply    # write
 */
import 'dotenv/config';
import { initFirebase, getFirestore } from '../src/firebase/admin.js';

const apply = process.argv.includes('--apply');
initFirebase();
const db = getFirestore();

const snap = await db.collection('emailLeads').get();
const plan = { review: [], website: [], both: [], neither: [], already: 0 };

for (const doc of snap.docs) {
  const have = doc.data().sourceType;
  if (have === 'review' || have === 'website') {
    plan.already += 1;
    continue;
  }
  const [inLeads, inWebsite] = await Promise.all([
    db.collection('leads').doc(doc.id).get(),
    db.collection('websiteLeads').doc(doc.id).get(),
  ]);
  if (inLeads.exists && inWebsite.exists) plan.both.push(doc.id);
  else if (inLeads.exists) plan.review.push(doc.id);
  else if (inWebsite.exists) plan.website.push(doc.id);
  else plan.neither.push(doc.id);
}

console.log(`emailLeads: ${snap.size} documents, ${plan.already} already have a sourceType`);
console.log(`  review: ${plan.review.length}  website: ${plan.website.length}  ambiguous: ${plan.both.length}  unknown: ${plan.neither.length}`);

if (!apply) {
  console.log('Dry run — nothing written. Re-run with --apply to write.');
  process.exit(0);
}

let written = 0;
for (const [sourceType, ids] of [['review', plan.review], ['website', plan.website]]) {
  for (let i = 0; i < ids.length; i += 400) {
    const batch = db.batch();
    for (const id of ids.slice(i, i + 400)) batch.update(db.collection('emailLeads').doc(id), { sourceType });
    await batch.commit();
    written += Math.min(400, ids.length - i);
  }
}
console.log(`Wrote sourceType on ${written} documents.`);
process.exit(0);
