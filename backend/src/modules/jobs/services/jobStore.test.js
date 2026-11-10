import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createJobStore } from './jobStore.js';
import { FakeFirestore } from '../testing/fakeFirestore.js';
import { buildJob } from '../adapters/buildJob.js';
import { COLLECTIONS } from '../models/constants.js';

const LONG_DESCRIPTION = Array.from({ length: 12 }, (_, i) => `We are hiring a Flutter developer to build mobile apps with Dart and Firebase, paragraph ${i} of the long description.`).join('\n');

/** A normalized job as an adapter would produce it. */
const job = (over = {}) =>
  buildJob({
    source: 'greenhouse',
    sourceJobId: '1001',
    sourceUrl: 'https://boards.greenhouse.io/acme/jobs/1001',
    applyUrl: 'https://boards.greenhouse.io/acme/jobs/1001',
    title: 'Flutter Developer',
    companyName: 'Acme Inc.',
    locationText: 'Los Angeles, CA',
    description: LONG_DESCRIPTION,
    postedAt: '2026-11-01T10:00:00Z',
    ...over,
  });

function harness() {
  const db = new FakeFirestore();
  let clock = new Date('2026-11-07T10:00:00Z');
  const store = createJobStore({ db, now: () => clock });
  return {
    db,
    store,
    tick: (ms = 3_600_000) => {
      clock = new Date(clock.getTime() + ms);
    },
  };
}

test('a new job is created once, with discovery metadata and null for what is unknown', async () => {
  const { store, db } = harness();
  const r = await store.upsertMany([job()], { runId: 'run1', searchId: 's1' });
  assert.deepEqual([r.new, r.updated, r.duplicate], [1, 0, 0]);
  const [[id, doc]] = db.dump(COLLECTIONS.jobs);
  assert.equal(id, doc.fingerprint);
  assert.equal(doc.status, 'active');
  assert.equal(doc.userState, 'new');
  assert.equal(doc.discoveredBy.runId, 'run1');
  assert.equal(doc.city, 'Los Angeles');
  assert.equal(doc.countryCode, 'US');
  assert.equal(doc.salaryMin, null, 'no salary was stated');
  assert.equal(doc.companyWebsite, null);
  assert.deepEqual(doc.sourceNames, ['greenhouse']);
  assert.equal(doc.applyUrl, 'https://boards.greenhouse.io/acme/jobs/1001');
});

test('the same posting seen again updates the one document: verified date moves, discovery does not', async () => {
  const { store, db, tick } = harness();
  await store.upsertMany([job()], { runId: 'run1' });
  const first = db.dump(COLLECTIONS.jobs)[0][1];
  tick();
  const r = await store.upsertMany([job()], { runId: 'run2' });
  assert.deepEqual([r.new, r.updated, r.duplicate], [0, 0, 1]);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 1);
  const after = db.dump(COLLECTIONS.jobs)[0][1];
  assert.equal(after.discoveredAt.getTime(), first.discoveredAt.getTime());
  assert.equal(after.discoveredBy.runId, 'run1', 'discovery history is preserved');
  assert.ok(after.lastVerifiedAt > first.lastVerifiedAt);
  assert.equal(after.lastRunId, 'run2');
  assert.equal(after.seenCount, 2);
});

test('a changed posting is an update, not a new job', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const r = await store.upsertMany([job({ salaryMin: 90000, salaryMax: 120000, salaryCurrency: 'USD', salaryPeriod: 'year' })]);
  assert.deepEqual([r.new, r.updated, r.duplicate], [0, 1, 0]);
  const doc = db.dump(COLLECTIONS.jobs)[0][1];
  assert.equal(doc.salaryMin, 90000);
  assert.equal(doc.salaryMinAnnual, 90000);
});

test('the same job from another source (different id and URL) merges by fingerprint and adds the source', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const r = await store.upsertMany([
    job({ source: 'jooble', sourceJobId: 'j-77', sourceUrl: 'https://jooble.org/desc/77', applyUrl: null, companyName: 'ACME', title: 'Flutter Developer (m/f/d)' }),
  ]);
  assert.deepEqual([r.new, r.updated, r.duplicate], [0, 1, 0]);
  const docs = db.dump(COLLECTIONS.jobs);
  assert.equal(docs.length, 1);
  const doc = docs[0][1];
  assert.deepEqual([...doc.sourceNames].sort(), ['greenhouse', 'jooble']);
  assert.equal(doc.sources.length, 2);
  assert.equal(doc.primarySource, 'greenhouse', 'the employer ATS stays authoritative');
  assert.equal(doc.applyUrl, 'https://boards.greenhouse.io/acme/jobs/1001');
});

test('the same source id is the same job even if the title or city changed', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const r = await store.upsertMany([job({ title: 'Senior Flutter Developer', locationText: 'San Francisco, CA' })]);
  assert.equal(r.new, 0);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 1);
});

test('the same direct application URL on a different source id is the same job', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const r = await store.upsertMany([
    job({ source: 'career_page', sourceJobId: 'page-1', title: 'Mobile Engineer', applyUrl: 'https://www.boards.greenhouse.io/acme/jobs/1001/?utm_source=x', sourceUrl: 'https://acme.com/careers/1' }),
  ]);
  assert.equal(r.new, 0);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 1);
});

test('different cities are different jobs', async () => {
  const { store, db } = harness();
  const r = await store.upsertMany([
    job({ sourceJobId: 'a', applyUrl: 'https://acme.com/a' }),
    job({ sourceJobId: 'b', applyUrl: 'https://acme.com/b', locationText: 'Houston, TX' }),
  ]);
  assert.equal(r.new, 2);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 2);
});

test('a near-identical description with a compatible location merges despite a different fingerprint', async () => {
  const { store, db } = harness();
  await store.upsertMany([job({ locationText: 'Los Angeles, CA' })]);
  // Same company+title, but this source only says "California, United States" (no city).
  const r = await store.upsertMany([
    job({ source: 'jooble', sourceJobId: 'x1', applyUrl: null, sourceUrl: 'https://jooble.org/desc/1', locationText: 'California, United States' }),
  ]);
  assert.equal(r.new, 0, 'merged by description similarity');
  assert.equal(db.dump(COLLECTIONS.jobs).length, 1);
});

test('same company+title with a different description in a compatible place stays separate', async () => {
  const { store, db } = harness();
  await store.upsertMany([job({ locationText: 'Los Angeles, CA' })]);
  const other = Array.from({ length: 12 }, (_, i) => `Completely unrelated duties about warehouse logistics and forklifts, line ${i}, with nothing in common at all.`).join('\n');
  const r = await store.upsertMany([job({ source: 'jooble', sourceJobId: 'x2', applyUrl: null, sourceUrl: 'https://jooble.org/desc/2', locationText: 'California, United States', description: other })]);
  assert.equal(r.new, 1);
});

test('duplicates inside one page collapse into a single document', async () => {
  const { store, db } = harness();
  const r = await store.upsertMany([job(), job({ source: 'jooble', sourceJobId: 'dup', applyUrl: null, sourceUrl: 'https://jooble.org/desc/9' }), job()]);
  assert.equal(r.new, 1);
  assert.equal(r.duplicate + r.updated, 2);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 1);
});

test('a re-sighting of an unchanged job writes one document (no key or raw churn)', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const before = db.writes;
  await store.upsertMany([job()]);
  assert.equal(db.writes - before, 1);
});

test('raw source payload is kept in a sub-collection, not on the job', async () => {
  const { store, db } = harness();
  await store.upsertMany([job({ raw: { id: 1001, anything: 'the source said' } })]);
  const [[id, doc]] = db.dump(COLLECTIONS.jobs);
  assert.equal(doc.raw, undefined);
  const raws = db.dump(`${COLLECTIONS.jobs}/${id}/raw`);
  assert.equal(raws.length, 1);
  assert.deepEqual(raws[0][1].payload, { id: 1001, anything: 'the source said' });
});

test('a job is only expired when every source reported it gone twice; a failing source changes nothing', async () => {
  const { store, db } = harness();
  await store.upsertMany([job(), job({ source: 'jooble', sourceJobId: 'j1', applyUrl: null, sourceUrl: 'https://jooble.org/desc/1' })]);
  const [[id]] = db.dump(COLLECTIONS.jobs);
  const gone = [{ source: 'greenhouse', sourceJobId: '1001', found: false }, { source: 'jooble', sourceJobId: 'j1', found: false }];

  // One source errored (found: null) -> nothing counted for it.
  await store.recordVerification(id, [{ source: 'greenhouse', sourceJobId: '1001', found: false }, { source: 'jooble', sourceJobId: 'j1', found: null }]);
  await store.recordVerification(id, [{ source: 'greenhouse', sourceJobId: '1001', found: false }, { source: 'jooble', sourceJobId: 'j1', found: null }]);
  assert.equal(db.dump(COLLECTIONS.jobs)[0][1].status, 'active');

  // Both say gone, once: not yet.
  await store.recordVerification(id, gone);
  assert.equal(db.dump(COLLECTIONS.jobs)[0][1].status, 'active');
  // Both say gone again: expired.
  const r = await store.recordVerification(id, gone);
  assert.equal(r.expired, true);
  assert.equal(db.dump(COLLECTIONS.jobs)[0][1].status, 'expired');
});

test('an expired job found again by a scan is reactivated, but a manual expiry is respected', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const [[id]] = db.dump(COLLECTIONS.jobs);
  await store.setStatus(id, 'expired', { source: 'verification' });
  await store.upsertMany([job()]);
  assert.equal(db.dump(COLLECTIONS.jobs)[0][1].status, 'active');
  await store.setStatus(id, 'expired', { source: 'manual' });
  await store.upsertMany([job()]);
  assert.equal(db.dump(COLLECTIONS.jobs)[0][1].status, 'expired');
});

test('a deleted job is not re-added by the next scan', async () => {
  const { store, db } = harness();
  await store.upsertMany([job()]);
  const [[id]] = db.dump(COLLECTIONS.jobs);
  await store.remove(id);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 0);
  const r = await store.upsertMany([job()]);
  assert.equal(r.new, 0);
  assert.equal(r.suppressed, 1);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 0);
  // Even from a different source with a different id, the fingerprint is remembered.
  const r2 = await store.upsertMany([job({ source: 'jooble', sourceJobId: 'zz', applyUrl: null, sourceUrl: 'https://jooble.org/desc/z' })]);
  assert.equal(r2.suppressed, 1);
});

test('jobs missing required identity are ignored, not stored half-empty', async () => {
  const { store, db } = harness();
  const r = await store.upsertMany([null, { title: 'x' }, job()]);
  assert.equal(r.new, 1);
  assert.equal(db.dump(COLLECTIONS.jobs).length, 1);
});
