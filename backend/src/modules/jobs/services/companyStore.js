/**
 * `companies` — employers seen in job postings. One document per normalized
 * company name, updated as postings are ingested (never erased: a website
 * learned from one source is kept when another doesn't know it).
 */

import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS } from '../models/constants.js';
import { companyKey, keyDocId } from '../utils/normalize.js';
import { fold } from '../utils/text.js';
import { notFound } from '../utils/errors.js';
import { getAllChunked, commitInBatches, serialize, stripUndefined } from './firestoreUtil.js';
import { pagedQuery } from './paging.js';

export const companyDocId = (name) => keyDocId(`co|${companyKey(name)}`);

const union = (a, b) => [...new Set([...(a || []), ...(b || [])])];

export function createCompanyStore({ db = null, now = () => new Date(), jobCounter = null } = {}) {
  const database = () => db || getFirestore();
  const col = () => database().collection(COLLECTIONS.companies);
  const api = (snap) => serialize({ id: snap.id, ...snap.data() });

  return {
    /** Records the employers of [jobs]; returns how many companies were new. */
    async recordSightings(jobs) {
      const byKey = new Map();
      for (const j of jobs) {
        if (!j?.companyName) continue;
        const key = companyKey(j.companyName);
        if (!key) continue;
        const entry = byKey.get(key) || { name: j.companyName, website: null, location: null, countries: new Set(), sources: new Set() };
        entry.website ||= j.companyWebsite || null;
        entry.location ||= j.companyLocation || null;
        if (j.countryCode) entry.countries.add(j.countryCode);
        entry.sources.add(j.source);
        byKey.set(key, entry);
      }
      if (!byKey.size) return { created: 0, touched: 0 };

      const stamp = now();
      const entries = [...byKey.entries()];
      const refs = entries.map(([, e]) => col().doc(companyDocId(e.name)));
      const snaps = await getAllChunked(database(), refs);
      let created = 0;
      const writes = entries.map(([key, e], i) => {
        const prev = snaps[i].exists ? snaps[i].data() : null;
        if (!prev) created += 1;
        return {
          ref: refs[i],
          data: stripUndefined({
            key,
            name: prev?.name || e.name,
            website: prev?.website || e.website,
            location: prev?.location || e.location,
            countries: union(prev?.countries, [...e.countries]).slice(0, 30),
            sources: union(prev?.sources, [...e.sources]),
            firstSeenAt: prev?.firstSeenAt || stamp,
            lastSeenAt: stamp,
            updatedAt: stamp,
          }),
        };
      });
      await commitInBatches(database(), writes, (batch, w) => batch.set(w.ref, w.data, { merge: true }));
      return { created, touched: writes.length };
    },

    async list({ limit, cursor, q } = {}) {
      const needle = fold(q);
      const page = await pagedQuery({
        db: database(),
        collection: COLLECTIONS.companies,
        sortField: 'lastSeenAt',
        limit,
        cursor,
        memoryFilter: needle ? (d) => fold(d.name).includes(needle) : null,
        scanFields: ['name'],
        mapDoc: api,
      });
      // Job counts are live aggregations (cheap) rather than a counter that can drift.
      if (jobCounter) {
        await Promise.all(
          page.items.map(async (c) => {
            c.jobCount = await jobCounter([['companyKey', '==', c.key]]).catch(() => null);
            c.activeJobCount = await jobCounter([['companyKey', '==', c.key], ['status', '==', 'active']]).catch(() => null);
          }),
        );
      }
      return page;
    },

    async get(id) {
      const snap = await col().doc(String(id)).get();
      if (!snap.exists) throw notFound('Company not found');
      return api(snap);
    },

    async count() {
      return (await col().count().get()).data().count;
    },
  };
}
