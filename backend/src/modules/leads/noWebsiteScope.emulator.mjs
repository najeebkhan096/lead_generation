// The no-website / 1-star separation, the validation resume flow and the salesman
// stats, run against the Firestore emulator (a real query engine), not a fake.
//
// Run: npm run test:emulator   (needs Java on PATH for the emulator)
import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

initializeApp({ projectId: 'demo-scope' });
const db = getFirestore();

const store = await import('./websiteLeadStore.js');
const { LEAD_SOURCES } = await import('./leadSources.js');
const { listCategories } = await import('../../lib/pagination.js');
const { startValidationJob, getJobSnapshot, cancelValidationJob, _resetValidationJobForTests } = await import('../validation/whatsapp/whatsappValidationJob.js');
const { launchAutoValidation } = await import('../validation/whatsapp/whatsappWebController.js');
const { startEmailValidationJob, getEmailJobSnapshot, _resetEmailValidationJobForTests } = await import('../validation/email/emailValidationJob.js');
const { launchEmailValidation } = await import('../validation/email/emailValidationController.js');
const runs = await import('../validation/validationRuns.js');
const { resumeRun, getUnfinishedRuns, launchers } = await import('../validation/validationRunsController.js');
const { loadSalesmanStats } = await import('../users/salesmanStats.js');
const { listContactedLeads, moveLeadBack } = await import('../users/contactedLeads.js');

const COLLECTIONS = ['websiteLeads', 'whatsappLeads', 'users', 'noWebsiteScanProgress', 'noWebsiteScans', 'validationRuns', 'leadChecks'];

async function wipe() {
  for (const name of COLLECTIONS) await db.recursiveDelete(db.collection(name));
}

const at = (iso) => Timestamp.fromDate(new Date(iso));
const put = (collection, id, data) => db.collection(collection).doc(id).set(data);
const get = async (collection, id) => (await db.collection(collection).doc(id).get()).data();
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(check, what, ms = 4000) {
  const end = Date.now() + ms;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > end) assert.fail(`timed out waiting for ${what}`);
    await wait(15);
  }
}

const site = (over = {}) => ({
  business: 'Biz', category: 'Cafe USA', location: 'Austin, TX', phone: '+15125550100',
  websiteStatus: 'missing', updatedAt: at('2026-11-10T10:00:00Z'), createdAt: at('2026-11-10T10:00:00Z'), ...over,
});

/** The scenario the real data has: a no-website scan for "home service", and a 1-star scan's side-finds. */
async function seedScopes() {
  await put('noWebsiteScanProgress', 'run1__home%20service', { category: 'home service', covered: {}, stats: {} });
  await put('websiteLeads', 'A', site({ business: 'A', scanModes: ['no_website'], updatedAt: at('2026-11-10T12:00:00Z') }));
  await put('websiteLeads', 'B', site({ business: 'B', scanModes: ['reviews'], updatedAt: at('2026-11-10T11:00:00Z') })); // 1-star side-find
  await put('websiteLeads', 'C', site({ business: 'C', scanModes: ['reviews', 'no_website'], location: 'Miami, FL', hasWhatsApp: true, whatsAppCheckedAt: at('2026-11-10T09:00:00Z'), updatedAt: at('2026-11-10T10:00:00Z') }));
  await put('websiteLeads', 'D', site({ business: 'D', category: 'home service USA', email: 'd@d.example', emailStatus: 'found', updatedAt: at('2026-11-10T09:00:00Z') })); // legacy, category has a no-website scan
  await put('websiteLeads', 'E', site({ business: 'E', category: 'Plumber USA', updatedAt: at('2026-11-10T08:00:00Z') })); // legacy, no no-website scan
  await put('websiteLeads', 'F', site({ business: 'F', scanModes: ['no_website'], websiteStatus: 'available', updatedAt: at('2026-11-10T07:00:00Z') }));
}

beforeEach(async () => {
  await wipe();
  store._resetScopeCaches();
  _resetValidationJobForTests();
  _resetEmailValidationJobForTests();
});

const names = (page) => page.leads.map((l) => l.business).sort();

// ---------------------------------------------------------------- scoping

test('lists: a no-website list holds only what a no-website scan found; 1-star side-finds stay out', async () => {
  await seedScopes();
  assert.deepEqual(names(await store.listWebsiteLeads({ scan: 'no_website' })), ['A', 'C', 'D']);
  // Without the scope it is everything confirmed missing (the old behaviour, still available).
  assert.deepEqual(names(await store.listWebsiteLeads({})), ['A', 'B', 'C', 'D', 'E']);
});

test('lists: category, verified and email narrow the scoped list, and the first page knows the total', async () => {
  await seedScopes();
  const cafe = await store.listWebsiteLeads({ scan: 'no_website', category: 'Cafe USA' });
  assert.deepEqual(names(cafe), ['A', 'C']);
  assert.equal(cafe.total, 2);
  const verified = await store.listWebsiteLeads({ scan: 'no_website', verified: true });
  assert.deepEqual(names(verified), ['C']);
  assert.equal(verified.total, 1);
  const withEmail = await store.listWebsiteLeads({ scan: 'no_website', withEmail: true });
  assert.deepEqual(names(withEmail), ['D']);
  assert.equal((await store.listWebsiteLeads({ scan: 'no_website' })).total, 3);
});

test('lists: paging walks the scoped list once, newest first, without repeats', async () => {
  await seedScopes();
  const seen = [];
  let cursor;
  for (let guard = 0; guard < 10; guard++) {
    const page = await store.listWebsiteLeads({ scan: 'no_website', limit: 1, cursor });
    seen.push(...page.leads.map((l) => l.business));
    cursor = page.nextCursor;
    if (!cursor) break;
  }
  assert.deepEqual(seen, ['A', 'C', 'D']);
});

test('categories: only the searches of no-website scans, with their counts', async () => {
  await seedScopes();
  assert.deepEqual(await store.listWebsiteScanCategories(), [
    { name: 'Cafe USA', count: 2 },
    { name: 'home service USA', count: 1 },
  ]);
  store._resetScopeCaches();
  assert.deepEqual(await store.listWebsiteScanCategories({ verified: true }), [{ name: 'Cafe USA', count: 1 }]);
});

test('categories: the 1-star WhatsApp list counts only 1-star leads', async () => {
  await put('whatsappLeads', 'w1', { category: 'Cafe USA', sourceType: 'review' });
  await put('whatsappLeads', 'w2', { category: 'Cafe USA', sourceType: 'review' });
  await put('whatsappLeads', 'w3', { category: 'Salon USA', sourceType: 'website' });
  assert.deepEqual(await listCategories(db, 'whatsappLeads', { force: true, where: [['sourceType', '==', 'review']] }), [{ name: 'Cafe USA', count: 2 }]);
  assert.equal((await listCategories(db, 'whatsappLeads', { force: true })).length, 2);
});

test('validation sees only the no-website scan\'s leads: unchecked lists and the per-state summary', async () => {
  await seedScopes();
  assert.deepEqual((await store.listUncheckedWhatsApp({})).map((l) => l.business).sort(), ['A', 'D']); // C is checked, B/E are out of scope
  assert.deepEqual((await store.listUncheckedWhatsApp({ category: 'Cafe USA' })).map((l) => l.business), ['A']);
  assert.deepEqual((await store.listUncheckedWhatsApp({ category: 'Cafe USA', states: ['FL'] })).map((l) => l.business), []);
  assert.deepEqual((await store.listUncheckedEmail({ category: 'Cafe USA' })).map((l) => l.business).sort(), ['A', 'C']);

  const wa = await store.summarizeWebsiteLeadValidation('whatsapp', { category: 'Cafe USA' });
  const byName = Object.fromEntries(wa.locations.map((l) => [l.name, l]));
  assert.deepEqual([byName.TX.eligible, byName.TX.checked, byName.TX.status], [1, 0, 'not_validated']);
  assert.deepEqual([byName.FL.eligible, byName.FL.checked, byName.FL.found, byName.FL.status], [1, 1, 1, 'validated']);
  assert.equal(wa.total, 1);
});

test('a lead validated for WhatsApp is tagged as a no-website scan\'s, a scan tags its finds, and a later scan adds to it', async () => {
  await seedScopes();
  await store.updateWebsiteLeadWhatsApp('D', { hasWhatsApp: true }); // legacy, in scope
  const d = await get('websiteLeads', 'D');
  assert.equal(d.hasWhatsApp, true);
  assert.ok(d.whatsAppCheckedAt);
  assert.deepEqual(d.scanModes, ['no_website']);

  await store.saveWebsiteLeads([{ business: 'New Biz', category: 'Cafe USA', location: 'TX', phone: '+15125550111', scanMode: 'reviews' }]);
  const first = (await db.collection('websiteLeads').where('business', '==', 'New Biz').get()).docs[0];
  assert.deepEqual(first.data().scanModes, ['reviews']);
  await store.saveWebsiteLeads([{ business: 'New Biz', category: 'Cafe USA', location: 'TX', phone: '+15125550111', scanMode: 'no_website' }]);
  assert.deepEqual((await first.ref.get()).data().scanModes, ['reviews', 'no_website']);
});

test('tagging already-validated leads: only a no-website scan\'s get the tag, and a dry run writes nothing', async () => {
  await put('noWebsiteScanProgress', 'r__home', { category: 'home service' });
  await put('websiteLeads', 'v1', site({ category: 'home service USA', hasWhatsApp: true })); // legacy, in scope
  await put('websiteLeads', 'v2', site({ category: 'Cafe USA', hasWhatsApp: true })); // legacy side-find
  await put('websiteLeads', 'v3', site({ category: 'home service USA', hasWhatsApp: true, scanModes: ['reviews'] })); // knows its origin
  const dry = await store.tagVerifiedNoWebsiteLeads({ apply: false });
  assert.deepEqual([dry.validated, dry.tagged], [3, 1]);
  assert.equal((await get('websiteLeads', 'v1')).scanModes, undefined);

  store._resetScopeCaches();
  await store.tagVerifiedNoWebsiteLeads({ apply: true });
  assert.deepEqual((await get('websiteLeads', 'v1')).scanModes, ['no_website']);
  assert.equal((await get('websiteLeads', 'v2')).scanModes, undefined);
  assert.deepEqual((await get('websiteLeads', 'v3')).scanModes, ['reviews']);
});

// ------------------------------------------- an interrupted run, and its resume

/** The real WhatsApp job, with the number check faked: "valid" unless the number ends in 9. */
function whatsAppJob({ cancelAfter } = {}) {
  const asked = [];
  const checkNumberFn = async (phone) => {
    asked.push(phone);
    if (cancelAfter && asked.length === cancelAfter) cancelValidationJob();
    return { checked: true, valid: !phone.endsWith('9') };
  };
  const startJob = (opts) => startValidationJob({ ...opts, checkNumberFn, recordCheckFn: async () => {} });
  const track = (o) => runs.trackRun({ ...o, tickMs: 15 });
  return { asked, deps: { startJob, track } };
}

const jobDone = () => until(() => getJobSnapshot()?.status !== 'running' && getJobSnapshot(), 'the job to end');

async function seedCafes(n = 6) {
  await put('noWebsiteScanProgress', 'r__cafe', { category: 'Cafe' });
  for (let i = 1; i <= n; i++) {
    await put('websiteLeads', `cafe${i}`, site({
      business: `Cafe ${i}`, phone: `+1512555010${i}`, scanModes: ['no_website'], updatedAt: at(`2026-11-10T1${i}:00:00Z`),
    }));
  }
}

test('cancel part-way, then resume: only the leads not yet checked are checked, none twice', async () => {
  await seedCafes(6);
  const first = whatsAppJob({ cancelAfter: 3 });
  const out = await launchAutoValidation({ collection: 'websiteLeads', category: 'Cafe USA', states: ['TX'] }, first.deps);
  assert.equal(out.started, true);
  const snap = await jobDone();
  assert.equal(snap.status, 'cancelled');
  assert.equal(snap.checked, 3);

  // The run is on record, stopped, with how far it got.
  const stopped = await until(async () => {
    const list = await runs.listUnfinished({ collection: 'websiteLeads', kind: 'whatsapp' });
    return list.find((r) => r.status === 'stopped' && r.checked === 3) || null;
  }, 'the stopped run to be saved');
  assert.deepEqual([stopped.category, stopped.states, stopped.total], ['Cafe USA', ['TX'], 6]);

  // Three leads carry their answer; three do not.
  const done = (await db.collection('websiteLeads').where('whatsAppCheckedAt', '>', at('2000-01-01T00:00:00Z')).get()).size;
  assert.equal(done, 3);

  // Resume through the controller, as the page's Resume button does.
  const second = whatsAppJob();
  const original = launchers.whatsapp;
  launchers.whatsapp = (args) => original(args, second.deps);
  let status; let body;
  try {
    await resumeRun({ params: { id: stopped.id } }, { status(code) { status = code; return this; }, json(b) { body = b; return this; } });
  } finally {
    launchers.whatsapp = original;
  }
  assert.equal(status, 202, JSON.stringify(body));
  assert.match(body.message, /^Resumed\./);
  assert.equal((await jobDone()).status, 'done');

  assert.equal(second.asked.length, 3, 'only the three that were left');
  assert.equal(new Set([...first.asked, ...second.asked]).size, 6, 'no number was asked about twice');
  assert.equal((await db.collection('websiteLeads').where('whatsAppCheckedAt', '>', at('2000-01-01T00:00:00Z')).get()).size, 6);
  // Verified numbers stay in websiteLeads: nothing is copied into the 1-star list.
  assert.equal((await db.collection('whatsappLeads').get()).size, 0);
  // Every number here is "on WhatsApp" in this fake, and each is flagged on its own lead.
  assert.equal((await db.collection('websiteLeads').where('hasWhatsApp', '==', true).get()).size, 6);

  // The old record is closed; the new run finishes cleanly; nothing is left to resume.
  assert.equal((await get('validationRuns', stopped.id)).status, 'done');
  await until(async () => (await runs.listUnfinished({ collection: 'websiteLeads' })).length === 0, 'no unfinished runs');
  await until(async () => (await db.collection('validationRuns').where('status', '==', 'done').get()).size === 2, 'both runs closed');
});

test('resuming a run with nothing left just closes it', async () => {
  await runs.saveRun({
    id: 'old', kind: 'whatsapp', collection: 'websiteLeads', category: 'Cafe USA', states: [], status: 'stopped',
    total: 1, checked: 1, found: 0, startedAt: Date.now() - 1000, updatedAt: Date.now() - 1000, instance: runs._INSTANCE,
  });
  let status; let body;
  await resumeRun({ params: { id: 'old' } }, { status(code) { status = code; return this; }, json(b) { body = b; return this; } });
  assert.equal(status, undefined); // a plain 200
  assert.match(body.message, /complete/);
  assert.equal((await get('validationRuns', 'old')).status, 'done');
});

test('a run left "running" by a backend that is gone is offered as interrupted; an archive run is resumed from its page', async () => {
  const gone = { host: 'old-machine', boot: 'dead' };
  await runs.saveRun({ id: 'crash', kind: 'whatsapp', collection: 'websiteLeads', category: 'Cafe USA', status: 'running', total: 9, checked: 4, found: 2, startedAt: Date.now(), updatedAt: Date.now(), instance: gone });
  await runs.saveRun({ id: 'arch', kind: 'whatsapp', collection: 'archive', archiveId: 'excel-1', category: 'Cafe', status: 'stopped', total: 5, checked: 1, found: 1, startedAt: Date.now(), updatedAt: Date.now(), instance: runs._INSTANCE });

  let body;
  await getUnfinishedRuns({ query: { collection: 'websiteLeads' } }, { json(b) { body = b; } });
  assert.deepEqual(body.runs.map((r) => [r.id, r.status, r.checked]), [['crash', 'interrupted', 4]]);
  await getUnfinishedRuns({ query: { collection: 'archive' } }, { json(b) { body = b; } });
  assert.equal(body.runs[0].archiveId, 'excel-1');

  let status; let reply;
  await resumeRun({ params: { id: 'arch' } }, { status(code) { status = code; return this; }, json(b) { reply = b; return this; } });
  assert.equal(status, 409);
  assert.match(reply.error, /archive page/);
  assert.equal((await get('validationRuns', 'arch')).status, 'stopped', 'left for the page to resume');
});

test('email: leads that were looked up are not asked again; a failed lookup is retried', async () => {
  await put('websiteLeads', 'e1', site({ business: 'Found Co', scanModes: ['no_website'] }));
  await put('websiteLeads', 'e2', site({ business: 'Nothing Co', scanModes: ['no_website'] }));
  await put('websiteLeads', 'e3', site({ business: 'Flaky Co', scanModes: ['no_website'] }));
  await put('websiteLeads', 'e4', site({ business: 'Side Find', scanModes: ['reviews'] }));

  const asked = [];
  const flaky = { fail: true };
  const discoverFn = async (lead) => {
    asked.push(lead.business);
    if (lead.business === 'Found Co') return { emails: [{ email: 'hi@found.example', source: 'web_search', foundOn: 'https://x.example' }], searched: true };
    if (lead.business === 'Flaky Co' && flaky.fail) throw new Error('timeout');
    return { emails: [], searched: true };
  };
  const deps = {
    startJob: (opts) => startEmailValidationJob({ ...opts, discoverFn, verifyFn: async () => ({ result: 'valid' }) }),
    track: (o) => runs.trackRun({ ...o, tickMs: 15 }),
  };
  const endOfJob = () => until(() => getEmailJobSnapshot()?.status !== 'running' && getEmailJobSnapshot(), 'the email job');

  const first = await launchEmailValidation({ category: 'Cafe USA' }, deps);
  assert.equal(first.started, true);
  assert.equal(first.result.total, 3, 'the 1-star side-find is not looked up');
  await endOfJob();
  assert.deepEqual(asked.sort(), ['Flaky Co', 'Found Co', 'Nothing Co']);
  assert.deepEqual((await get('websiteLeads', 'e1')).email, 'hi@found.example');
  assert.equal((await get('websiteLeads', 'e2')).emailStatus, 'not_found');
  assert.equal((await get('websiteLeads', 'e3')).emailStatus, 'check_failed');

  // Run it again: only the failed one is tried.
  flaky.fail = false;
  asked.length = 0;
  _resetEmailValidationJobForTests();
  const second = await launchEmailValidation({ category: 'Cafe USA' }, deps);
  assert.equal(second.result.total, 1);
  await endOfJob();
  assert.deepEqual(asked, ['Flaky Co']);
  assert.equal((await get('websiteLeads', 'e3')).emailStatus, 'not_found');

  const summary = await store.summarizeWebsiteLeadValidation('email', { category: 'Cafe USA' });
  assert.deepEqual([summary.locations[0].eligible, summary.locations[0].checked, summary.locations[0].found, summary.total], [3, 3, 1, 0]);
});

// ------------------------------------------------------- salesman records

test('salesman stats: both kinds, the shared today count, the pool sizes, and a missing user', async () => {
  const now = new Date();
  const earlier = new Date(now.getTime() - 3 * 86400_000);
  await put('users', 'ali', { name: 'Ali', email: 'ali@x.test', role: 'salesman', approved: true, dailyLeadLimit: 5 });
  await put('users', 'bo', { name: 'Bo', email: 'bo@x.test', role: 'salesman', approved: true });
  await put('whatsappLeads', 'r1', { sourceType: 'review', status: 'contacted', contactedBy: 'ali', contactedAt: Timestamp.fromDate(now) });
  await put('whatsappLeads', 'r2', { sourceType: 'review', status: 'contacted', contactedBy: 'ali', contactedAt: Timestamp.fromDate(earlier) });
  await put('whatsappLeads', 'r3', { sourceType: 'review', status: 'lead' });
  await put('websiteLeads', 'w1', { websiteStatus: 'missing', hasWhatsApp: true, status: 'contacted', contactedBy: 'ali', contactedAt: Timestamp.fromDate(now) });
  await put('websiteLeads', 'w2', { websiteStatus: 'missing', hasWhatsApp: true, status: 'contacted', contactedBy: 'bo', contactedAt: Timestamp.fromDate(earlier) });
  await put('websiteLeads', 'w3', { websiteStatus: 'missing', hasWhatsApp: true, status: 'lead' });
  await put('websiteLeads', 'w4', { websiteStatus: 'missing', hasWhatsApp: false }); // not verified: not in the pool

  const stats = await loadSalesmanStats({ days: 14, now });
  const ali = stats.salesmen.find((s) => s.id === 'ali');
  assert.deepEqual(ali.byKind.review, { today: 1, last7: 2, total: 2 });
  assert.deepEqual(ali.byKind.website, { today: 1, last7: 1, total: 1 });
  assert.equal(ali.contactedToday, 2);
  assert.equal(ali.limitLeftToday, 3);
  assert.equal(stats.totals.websiteLeads, 3);
  assert.equal(stats.totals.websiteNewLeft, 1);
  assert.equal(stats.totals.reviewLeads, 3);
  assert.equal(stats.totals.newLeft, 1);
  assert.equal(stats.totals.byKind.website.total, 2);
  assert.equal(stats.totals.contactedTotal, 4);
});

test('contacted leads: both kinds, newest first; moving one back touches only its own collection', async () => {
  await put('whatsappLeads', 'same', { business: 'Review Twin', sourceType: 'review', status: 'contacted', contactedBy: 'ali', contactedAt: at('2026-11-10T09:00:00Z') });
  await put('websiteLeads', 'same', { business: 'Site Twin', status: 'contacted', contactedBy: 'ali', contactedAt: at('2026-11-10T10:00:00Z') });
  await put('websiteLeads', 'other', { business: 'Not Ali', status: 'contacted', contactedBy: 'bo', contactedAt: at('2026-11-10T11:00:00Z') });

  const list = await listContactedLeads('ali');
  assert.deepEqual(list.map((l) => [l.business, l.kind]), [['Site Twin', 'website'], ['Review Twin', 'review']]);

  const moved = await moveLeadBack('ali', 'same', { kind: 'website' });
  assert.equal(moved.kind, 'website');
  assert.equal((await get('websiteLeads', 'same')).status, 'lead');
  assert.equal((await get('websiteLeads', 'same')).contactedBy, undefined);
  assert.equal((await get('whatsappLeads', 'same')).status, 'contacted', 'the 1-star twin is untouched');
  assert.deepEqual((await listContactedLeads('ali')).map((l) => l.kind), ['review']);
  await assert.rejects(moveLeadBack('bo', 'same', { kind: 'website' }), (e) => e.status === 409);
});

test('a validation source reads and writes the right collection', async () => {
  await put('websiteLeads', 's1', site({ business: 'S1', scanModes: ['no_website'] }));
  const loaded = await LEAD_SOURCES.websiteLeads.load(['s1', 'missing']);
  assert.deepEqual(loaded.map((l) => l.id), ['s1']);
  assert.equal(loaded[0].sourceType, 'website');
});
