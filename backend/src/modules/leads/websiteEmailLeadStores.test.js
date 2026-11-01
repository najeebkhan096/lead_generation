import { test } from 'node:test';
import assert from 'node:assert/strict';
import { saveWebsiteLeads, markWebsiteAvailable, buildWebsiteLeadPatch, websiteLeadDocId } from './websiteLeadStore.js';
import { saveEmailResult, buildEmailLeadPatch, mergeEmails, emailLeadDocId } from './emailLeadStore.js';
import { isEmailCheckFresh, EMAIL_RECHECK_DAYS } from '../validation/leadChecks.js';
import { leadDocId } from '../../lib/leadIdentity.js';

/** An in-memory stand-in for the slice of Firestore the stores use. */
function fakeDb() {
  const data = new Map(); // "collection/id" -> object
  const makeRef = (collection, id) => ({
    id,
    key: `${collection}/${id}`,
    async get() {
      const value = data.get(`${collection}/${id}`);
      return { id, exists: value !== undefined, data: () => (value === undefined ? undefined : structuredClone(value)) };
    },
    async set(patch, opts = {}) {
      const prior = opts.merge ? data.get(`${collection}/${id}`) || {} : {};
      data.set(`${collection}/${id}`, { ...prior, ...patch });
    },
    async delete() {
      data.delete(`${collection}/${id}`);
    },
  });
  return {
    data,
    collection: (c) => ({ doc: (id) => makeRef(c, id) }),
    getAll: (...refs) => Promise.all(refs.map((r) => r.get())),
    batch() {
      const ops = [];
      return { set: (ref, patch, opts) => ops.push(() => ref.set(patch, opts)), commit: async () => { for (const op of ops) await op(); } };
    },
    count: (collection) => [...data.keys()].filter((k) => k.startsWith(`${collection}/`)).length,
  };
}

const site = (extra = {}) => ({
  business: "Joe's Plumbing",
  category: 'Plumber',
  location: 'Texas',
  address: '1 Main St, Austin, TX',
  phone: '+15125550100',
  waLink: 'https://wa.me/15125550100',
  mapsUrl: 'https://www.google.com/maps/place/joes/data=!1',
  rating: 4.2,
  totalReviews: 18,
  source: 'google_maps',
  website: null,
  leadTypes: [],
  ...extra,
});

const NOW1 = new Date('2026-10-01T10:00:00Z');
const NOW2 = new Date('2026-10-10T10:00:00Z');

// ---- website leads ---------------------------------------------------------

test('a no-website business is saved once, with an explicit "missing" status', async () => {
  const db = fakeDb();
  const r = await saveWebsiteLeads([site()], { db, now: NOW1 });
  assert.deepEqual(r, { inserted: 1, updated: 0 });
  const doc = db.data.get(`websiteLeads/${websiteLeadDocId(site())}`);
  assert.equal(doc.websiteStatus, 'missing');
  assert.equal(doc.business, "Joe's Plumbing");
  assert.equal(doc.category, 'Plumber USA');
  assert.equal(doc.phone, '+15125550100');
  assert.equal(doc.mapsUrl, site().mapsUrl);
  assert.equal(doc.rating, 4.2);
  assert.deepEqual(doc.leadTypes, ['no_website']);
});

test('rescanning the same business updates its document: no duplicate, createdAt kept', async () => {
  const db = fakeDb();
  await saveWebsiteLeads([site()], { db, now: NOW1 });
  const r = await saveWebsiteLeads([site({ rating: 4.5 })], { db, now: NOW2 });
  assert.deepEqual(r, { inserted: 0, updated: 1 });
  assert.equal(db.count('websiteLeads'), 1);
  const doc = db.data.get(`websiteLeads/${websiteLeadDocId(site())}`);
  assert.equal(doc.rating, 4.5);
  assert.equal(doc.createdAt, NOW1);
  assert.equal(doc.updatedAt, NOW2);
});

test('a thinner rescan never blanks stored details', async () => {
  const db = fakeDb();
  await saveWebsiteLeads([site()], { db, now: NOW1 });
  await saveWebsiteLeads([site({ phone: null, waLink: null, address: '' })], { db, now: NOW2 });
  const doc = db.data.get(`websiteLeads/${websiteLeadDocId(site())}`);
  assert.equal(doc.phone, '+15125550100');
  assert.equal(doc.address, '1 Main St, Austin, TX');
});

test('the same business listed twice in one batch is one document', async () => {
  const db = fakeDb();
  const r = await saveWebsiteLeads([site(), site()], { db, now: NOW1 });
  assert.equal(r.inserted, 1);
  assert.equal(db.count('websiteLeads'), 1);
});

test('a business that is also a review lead carries both classifications, under one id per collection', async () => {
  const db = fakeDb();
  await saveWebsiteLeads([site({ leadTypes: ['review'] })], { db, now: NOW1 });
  const doc = db.data.get(`websiteLeads/${websiteLeadDocId(site())}`);
  assert.deepEqual(doc.leadTypes, ['no_website', 'review']);
  assert.equal(websiteLeadDocId(site()), leadDocId(site()), 'same id the review lead has in `leads`');
});

test('a no-website lead whose business later shows a website is re-labelled, not deleted', async () => {
  const db = fakeDb();
  await saveWebsiteLeads([site()], { db, now: NOW1 });
  assert.equal(await markWebsiteAvailable(site(), 'https://joes.test/', { db, now: NOW2 }), true);
  const doc = db.data.get(`websiteLeads/${websiteLeadDocId(site())}`);
  assert.equal(doc.websiteStatus, 'available');
  assert.equal(doc.business, "Joe's Plumbing", 'document kept');
  assert.equal(await markWebsiteAvailable(site({ mapsUrl: 'https://other' }), 'https://x.test/', { db }), false, 'no such lead: nothing written');
  assert.equal(db.count('websiteLeads'), 1);
});

test('nothing is written for an empty batch or a nameless business', async () => {
  const db = fakeDb();
  assert.deepEqual(await saveWebsiteLeads([], { db }), { inserted: 0, updated: 0 });
  assert.deepEqual(await saveWebsiteLeads([{ phone: '+1' }], { db }), { inserted: 0, updated: 0 });
  assert.equal(db.count('websiteLeads'), 0);
  assert.equal(buildWebsiteLeadPatch(undefined, site(), NOW1).createdAt, NOW1);
});

// ---- email leads -----------------------------------------------------------

const found = (...addresses) => ({
  status: 'found',
  reason: null,
  website: 'https://joes.test/',
  emails: addresses.map((a, i) => ({ address: a, sourceUrl: i === 0 ? 'https://joes.test/' : 'https://joes.test/contact' })),
});
const websiteSite = (extra = {}) => site({ website: 'https://joes.test/', ...extra });

test('a found email is saved with its source page, status and the business details', async () => {
  const db = fakeDb();
  assert.equal(await saveEmailResult(websiteSite(), found('info@joes.test'), { db, now: NOW1 }), 'inserted');
  const doc = db.data.get(`emailLeads/${emailLeadDocId(websiteSite())}`);
  assert.equal(doc.emailStatus, 'found');
  assert.equal(doc.email, 'info@joes.test');
  assert.equal(doc.emailSourceUrl, 'https://joes.test/');
  assert.equal(doc.website, 'https://joes.test/');
  assert.equal(doc.websiteStatus, 'available');
  assert.equal(doc.phone, '+15125550100');
  assert.deepEqual(doc.emails.map((e) => e.address), ['info@joes.test']);
});

test('multiple addresses are stored in one consistent list', async () => {
  const db = fakeDb();
  await saveEmailResult(websiteSite(), found('info@joes.test', 'sales@joes.test'), { db, now: NOW1 });
  const doc = db.data.get(`emailLeads/${emailLeadDocId(websiteSite())}`);
  assert.deepEqual(doc.emails.map((e) => [e.address, e.sourceUrl]), [
    ['info@joes.test', 'https://joes.test/'],
    ['sales@joes.test', 'https://joes.test/contact'],
  ]);
  assert.equal(doc.email, 'info@joes.test', 'the first is the headline address');
});

test('rescanning does not duplicate: same document, addresses merged, first source kept', async () => {
  const db = fakeDb();
  await saveEmailResult(websiteSite(), found('info@joes.test'), { db, now: NOW1 });
  const res = await saveEmailResult(
    websiteSite(),
    { ...found('info@joes.test', 'new@joes.test'), emails: [{ address: 'info@joes.test', sourceUrl: 'https://joes.test/about' }, { address: 'new@joes.test', sourceUrl: 'https://joes.test/about' }] },
    { db, now: NOW2 }
  );
  assert.equal(res, 'updated');
  assert.equal(db.count('emailLeads'), 1);
  const doc = db.data.get(`emailLeads/${emailLeadDocId(websiteSite())}`);
  assert.deepEqual(doc.emails.map((e) => e.address), ['info@joes.test', 'new@joes.test']);
  assert.equal(doc.emails[0].sourceUrl, 'https://joes.test/', 'first source kept');
  assert.equal(doc.createdAt, NOW1);
});

test('a later check that finds nothing or fails never erases a saved email', async () => {
  for (const later of [
    { status: 'not_found', reason: null, emails: [] },
    { status: 'check_failed', reason: 'timeout', emails: [] },
    { status: 'check_failed', reason: 'blocked', emails: [] },
    { status: 'not_checked', reason: 'robots_disallowed', emails: [] },
  ]) {
    const db = fakeDb();
    await saveEmailResult(websiteSite(), found('info@joes.test'), { db, now: NOW1 });
    await saveEmailResult(websiteSite(), later, { db, now: NOW2 });
    const doc = db.data.get(`emailLeads/${emailLeadDocId(websiteSite())}`);
    assert.equal(doc.email, 'info@joes.test', later.status);
    assert.deepEqual(doc.emails.map((e) => e.address), ['info@joes.test'], later.status);
    assert.equal(doc.emailStatus, 'found', later.status);
    assert.equal(doc.lastCheckStatus, later.status, 'the failed attempt is noted');
    assert.equal(doc.lastCheckReason, later.reason ?? null);
  }
});

test('a business with no email gets no email-lead document', async () => {
  const db = fakeDb();
  assert.equal(await saveEmailResult(websiteSite(), { status: 'not_found', reason: null, emails: [] }, { db, now: NOW1 }), 'unchanged');
  assert.equal(await saveEmailResult(websiteSite(), { status: 'check_failed', reason: 'timeout', emails: [] }, { db, now: NOW1 }), 'unchanged');
  assert.equal(db.count('emailLeads'), 0);
  assert.equal(buildEmailLeadPatch(undefined, websiteSite(), { status: 'not_found', emails: [] }), null);
});

test('mergeEmails de-duplicates case-insensitively and caps the list', () => {
  const merged = mergeEmails([{ address: 'A@x.com', sourceUrl: 's1', foundAt: 't0' }], [{ address: 'a@x.com', sourceUrl: 's2' }, { address: 'b@x.com', sourceUrl: 's2' }], 't1');
  assert.deepEqual(merged.map((e) => [e.address, e.sourceUrl, e.foundAt]), [['a@x.com', 's1', 't0'], ['b@x.com', 's2', 't1']]);
  const many = mergeEmails([], Array.from({ length: 30 }, (_, i) => ({ address: `p${i}@x.com`, sourceUrl: 's' })), 't');
  assert.equal(many.length, 10);
});

// ---- check memory ------------------------------------------------------------

test('a recent email check is reused: found and not_found for a month, failures only briefly', () => {
  const at = (days) => ({ toMillis: () => Date.now() - days * 86400000 });
  assert.equal(isEmailCheckFresh({ status: 'found', at: at(5) }), true);
  assert.equal(isEmailCheckFresh({ status: 'not_found', at: at(5) }), true);
  assert.equal(isEmailCheckFresh({ status: 'not_found', at: at(EMAIL_RECHECK_DAYS.not_found + 1) }), false);
  assert.equal(isEmailCheckFresh({ status: 'check_failed', at: at(1) }), true);
  assert.equal(isEmailCheckFresh({ status: 'check_failed', at: at(3) }), false, 'a failed check comes back soon');
  assert.equal(isEmailCheckFresh(undefined), false);
  assert.equal(isEmailCheckFresh({ status: 'weird', at: at(0) }), false);
});
