/**
 * One-time migration: re-normalizes phone numbers for leads saved while
 * `normalizeUsPhone` was still US-only (see whatsappChecker.js). For any
 * non-US/CA lead, that old code passed the raw scraped digits through
 * unchanged and prefixed a '+' — e.g. a German local number "030
 * 12106017" got stored as the bogus "+03012106017" instead of the real
 * "+493012106017".
 *
 * Because the old code was a no-op pass-through (never actually
 * transformed the digits), the digits currently stored (minus the
 * leading '+') ARE the original raw scrape — recoverable and re-fixable
 * here with the country-aware `normalizePhone`, using the country each
 * lead's category is already tagged with (e.g. "car wash Germany").
 *
 * Usage:
 *   node scripts/fixInternationalPhones.js            # dry run, no writes
 *   node scripts/fixInternationalPhones.js --apply     # actually writes
 */

import { initFirebase, getFirestore } from '../src/firebase/admin.js';
import { COUNTRIES } from '../src/data/countries.js';
import { normalizePhone, waMeLink } from '../src/services/whatsappChecker.js';

initFirebase();

const COUNTRY_LIST = Object.values(COUNTRIES).sort((a, b) => b.shortName.length - a.shortName.length);

function countryFromCategory(category) {
  const cat = String(category || '');
  for (const c of COUNTRY_LIST) {
    if (cat.endsWith(` ${c.shortName}`)) return c.code;
  }
  return null;
}

function recoverRawDigits(storedPhone) {
  return String(storedPhone || '').replace(/^\+/, '');
}

async function main() {
  const dryRun = !process.argv.includes('--apply');
  const db = getFirestore();

  const stats = {
    scanned: 0,
    changed: 0,
    noPhone: 0,
    noCountryMatch: 0,
    nanpSkipped: 0,
    alreadyCorrect: 0,
    couldNotFix: 0,
  };

  let lastDoc = null;
  const pageSize = 400;

  console.log(dryRun ? 'DRY RUN — no writes will be made.\n' : 'APPLY MODE — writing changes.\n');

  while (true) {
    let query = db.collection('leads').orderBy('__name__').limit(pageSize);
    if (lastDoc) query = query.startAfter(lastDoc);
    const snap = await query.get();
    if (snap.empty) break;

    const batch = db.batch();
    let batchHasWrites = false;

    for (const doc of snap.docs) {
      stats.scanned += 1;
      const d = doc.data();

      if (!d.phone) {
        stats.noPhone += 1;
        continue;
      }

      const country = countryFromCategory(d.category);
      if (!country) {
        stats.noCountryMatch += 1;
        continue;
      }
      if (country === 'US' || country === 'CA') {
        stats.nanpSkipped += 1;
        continue;
      }

      const fixed = normalizePhone(recoverRawDigits(d.phone), country);
      if (!fixed) {
        stats.couldNotFix += 1;
        continue;
      }

      const newPhone = `+${fixed}`;
      if (newPhone === d.phone) {
        stats.alreadyCorrect += 1;
        continue;
      }

      stats.changed += 1;
      console.log(`${doc.id}  ${d.phone} -> ${newPhone}   (${d.business} — ${d.category})`);

      if (!dryRun) {
        batch.update(doc.ref, { phone: newPhone, waLink: waMeLink(fixed) });
        batchHasWrites = true;
      }
    }

    if (!dryRun && batchHasWrites) {
      await batch.commit();
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < pageSize) break;
  }

  console.log('\n--- summary ---');
  console.log('scanned:            ', stats.scanned);
  console.log('changed:            ', stats.changed, dryRun ? '(dry run — nothing written)' : '(written)');
  console.log('no phone:           ', stats.noPhone);
  console.log('no country match:   ', stats.noCountryMatch);
  console.log('US/CA (already ok): ', stats.nanpSkipped);
  console.log('already correct:    ', stats.alreadyCorrect);
  console.log('could not fix:      ', stats.couldNotFix);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
