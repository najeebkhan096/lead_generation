/**
 * One-off: populate the `whatsappLeads` collection from data that was
 * verified before that collection existed.
 *
 * Sources (all already confirmed on WhatsApp, so nothing is re-checked):
 *   1. `leads` documents with `hasWhatsApp == true`
 *   2. `websiteLeads` documents with `hasWhatsApp == true`
 *   3. every "WhatsApp Verified" archive (`whatsappValidatedScans` workbooks)
 *
 * Safe to re-run: documents are upserted by the same deterministic id the
 * validator uses, so a business found in several sources is one document
 * and nothing is duplicated. Source documents are never modified.
 *
 *   node scripts/backfillWhatsappLeads.js            # dry run — counts only
 *   node scripts/backfillWhatsappLeads.js --apply    # writes to Firestore
 *
 * NOTE: uses whatever Firebase credentials this machine's backend uses —
 * i.e. production, if backend/firebase-service-account.json is configured.
 */

import { initFirebase, getFirestore } from '../src/firebase/admin.js';
import { saveWhatsAppLeadsToFirebase } from '../src/modules/validation/whatsapp/whatsappLeadStore.js';
import {
  listValidatedArchives,
  downloadValidatedArchiveBuffer,
} from '../src/modules/validation/whatsapp/whatsappValidatedStore.js';
import { xlsxBufferToJson, sheetsToLeadsJson } from '../src/modules/archive/exportService.js';
import { leadDocId } from '../src/lib/leadIdentity.js';

const apply = process.argv.includes('--apply');

function fromSavedDoc(doc, sourceType) {
  const d = doc.data();
  return {
    id: doc.id,
    dbId: doc.id,
    business: d.business,
    category: d.category,
    location: d.location,
    address: d.address,
    phone: d.phone,
    website: d.website,
    mapsUrl: d.mapsUrl,
    rating: d.rating,
    totalReviews: d.totalReviews,
    waLink: d.waLink,
    badReview: d.badReview,
    source: d.source,
    sourceType,
  };
}

async function main() {
  initFirebase();
  const db = getFirestore();
  const byId = new Map();
  const counts = { leads: 0, websiteLeads: 0, archives: 0, archiveLeads: 0 };

  const add = (lead) => {
    if (!lead.phone) return;
    // First source wins — saved leads carry the richest data and run first.
    const id = leadDocId(lead);
    if (!byId.has(id)) byId.set(id, lead);
  };

  for (const [collection, sourceType] of [['leads', 'review'], ['websiteLeads', 'website']]) {
    const snap = await db.collection(collection).where('hasWhatsApp', '==', true).get();
    snap.docs.forEach((doc) => add(fromSavedDoc(doc, sourceType)));
    counts[collection] = snap.size;
  }

  const archives = await listValidatedArchives();
  counts.archives = archives.length;
  for (const archive of archives) {
    try {
      const found = await downloadValidatedArchiveBuffer(archive.id);
      if (!found) continue;
      const sheets = await xlsxBufferToJson(found.buffer);
      const leads = sheetsToLeadsJson(sheets, `wa-verified-${archive.id}`);
      leads.forEach((l) => add({ ...l, dbId: null, sourceType: l.badReview?.text ? 'review' : 'website' }));
      counts.archiveLeads += leads.length;
    } catch (err) {
      console.warn(`  skipped archive ${archive.fileName || archive.id}: ${err.message}`);
    }
  }

  console.log('Found:', counts);
  console.log(`Unique verified businesses to write: ${byId.size}`);

  if (!apply) {
    console.log('\nDry run — nothing written. Re-run with --apply to write to `whatsappLeads`.');
    return;
  }
  const result = await saveWhatsAppLeadsToFirebase([...byId.values()]);
  console.log('Written:', result);
}

main().then(() => process.exit(0)).catch((err) => {
  console.error(err);
  process.exit(1);
});
