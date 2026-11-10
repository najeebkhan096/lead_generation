/**
 * `job_alerts` — saved filters that are checked against the jobs a scan newly
 * discovers. A match is recorded on the alert (count, recent job ids); the UI
 * shows it and, if an email is set, a notifier can pick it up from there.
 */

import crypto from 'node:crypto';
import { getFirestore } from '../../../firebase/admin.js';
import { COLLECTIONS } from '../models/constants.js';
import { notFound } from '../utils/errors.js';
import { fold } from '../utils/text.js';
import { serialize, stripUndefined } from './firestoreUtil.js';
import { pagedQuery } from './paging.js';

/** Does a stored job satisfy an alert's filters? Pure; used on a scan's new jobs. */
export function jobMatchesAlert(job, filters) {
  const f = filters || {};
  if (f.countryCode && job.countryCode !== f.countryCode) return false;
  if (f.state && fold(job.state) !== fold(f.state)) return false;
  if (f.city && fold(job.city) !== fold(f.city)) return false;
  if (f.workArrangement && job.workArrangement !== f.workArrangement) return false;
  if (f.employmentType && job.employmentType !== f.employmentType) return false;
  if (f.experienceLevel && job.experienceLevel !== f.experienceLevel) return false;
  if (f.source && !(job.sourceNames || []).includes(f.source)) return false;
  if (f.salaryMin != null && !((job.salaryMaxAnnual ?? -1) >= f.salaryMin)) return false;
  if (f.skills?.length) {
    const have = new Set([...(job.requiredSkills || []), ...(job.preferredSkills || [])].map((s) => s.toLowerCase()));
    if (!f.skills.every((s) => have.has(String(s).toLowerCase()))) return false;
  }
  if (f.q) {
    const hay = fold([job.title, job.companyName, job.locationText, ...(job.requiredSkills || [])].join(' '));
    if (!fold(f.q).split(' ').filter(Boolean).every((w) => hay.includes(w))) return false;
  }
  return true;
}

export function createAlertStore({ db = null, now = () => new Date() } = {}) {
  const database = () => db || getFirestore();
  const col = () => database().collection(COLLECTIONS.alerts);
  const api = (snap) => serialize({ id: snap.id, ...snap.data() });

  return {
    async create(config) {
      const id = `a_${crypto.randomBytes(8).toString('hex')}`;
      const stamp = now();
      await col().doc(id).create(stripUndefined({ ...config, createdAt: stamp, updatedAt: stamp, lastMatchAt: null, lastMatchCount: 0, totalMatches: 0, recentJobIds: [] }));
      return api(await col().doc(id).get());
    },

    async update(id, config) {
      const ref = col().doc(String(id));
      if (!(await ref.get()).exists) throw notFound('Alert not found');
      await ref.set(stripUndefined({ ...config, updatedAt: now() }), { merge: true });
      return api(await ref.get());
    },

    async remove(id) {
      const ref = col().doc(String(id));
      const snap = await ref.get();
      if (!snap.exists) throw notFound('Alert not found');
      await ref.delete();
      return { id: snap.id };
    },

    async get(id) {
      const snap = await col().doc(String(id)).get();
      if (!snap.exists) throw notFound('Alert not found');
      return api(snap);
    },

    async list({ limit, cursor } = {}) {
      return pagedQuery({ db: database(), collection: COLLECTIONS.alerts, sortField: 'updatedAt', limit, cursor, mapDoc: api });
    },

    async listEnabled() {
      const snap = await col().where('enabled', '==', true).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    },

    /**
     * Checks enabled alerts against freshly discovered jobs ([{id, ...doc}]) and
     * records matches. Returns [{alertId, matches}] for alerts that matched.
     */
    async evaluate(newJobs) {
      if (!newJobs.length) return [];
      const stamp = now();
      const hits = [];
      for (const alert of await this.listEnabled()) {
        const matched = newJobs.filter((j) => jobMatchesAlert(j, alert.filters));
        if (!matched.length) continue;
        await col().doc(alert.id).set(
          {
            lastMatchAt: stamp,
            lastMatchCount: matched.length,
            totalMatches: (alert.totalMatches || 0) + matched.length,
            recentJobIds: [...matched.map((j) => j.id), ...(alert.recentJobIds || [])].slice(0, 25),
            updatedAt: stamp,
          },
          { merge: true },
        );
        hits.push({ alertId: alert.id, matches: matched.length });
      }
      return hits;
    },
  };
}
