import { test } from 'node:test';
import assert from 'node:assert/strict';
import { recordCityWebsites, classifyBusinesses, websiteStatusOf } from './siteLeadPipeline.js';
import { _scanStateCities as scanStateCities, _newStateRecord as newStateRecord } from '../scan/stateCityOrchestrator.js';

const biz = (name, extra = {}) => ({
  name,
  category: 'Plumber',
  address: '1 Main St',
  phone: '(512) 555-0100',
  website: null,
  websiteStatus: 'missing',
  mapsUrl: `https://www.google.com/maps/place/${encodeURIComponent(name)}`,
  rating: 4.4,
  totalReviews: 30,
  source: 'google_maps',
  ...extra,
});

function deps(overrides = {}) {
  const saved = [];
  const unknown = [];
  const queued = [];
  return {
    saved,
    unknown,
    queued,
    opts: {
      state: 'Texas',
      enabled: true,
      log: () => {},
      saveWebsiteLeadsFn: async (sites) => {
        saved.push(...sites);
        return { inserted: sites.length, updated: 0 };
      },
      recordUnknownFn: async (s, info) => unknown.push([s.business, info.reason]),
      queue: { enqueue: (s) => (queued.push(s), 'queued') },
      ...overrides,
    },
  };
}

test('a business with no website is a website lead; one with a website goes to the email queue', async () => {
  const d = deps();
  const summary = await recordCityWebsites(
    [biz('No Site'), biz('Has Site', { website: 'https://hassite.test', websiteStatus: 'available' })],
    d.opts
  );
  assert.deepEqual(d.saved.map((s) => s.business), ['No Site']);
  assert.deepEqual(d.queued.map((s) => s.business), ['Has Site']);
  assert.equal(d.queued[0].website, 'https://hassite.test');
  assert.deepEqual(summary, { missing: 1, available: 1, unknown: 0, saved: 1, queued: 1 });
});

test('a website that could not be determined is never saved as a website lead', async () => {
  const d = deps();
  const summary = await recordCityWebsites([biz('Maybe', { websiteStatus: 'unknown' })], d.opts);
  assert.deepEqual(d.saved, []);
  assert.deepEqual(d.queued, []);
  assert.deepEqual(d.unknown, [['Maybe', 'listing_not_fully_read']]);
  assert.equal(summary.unknown, 1);
});

test('a scraper that does not state the status never yields "missing"', () => {
  assert.equal(websiteStatusOf({ name: 'x', website: null }), 'unknown');
  assert.equal(websiteStatusOf({ name: 'x', website: 'https://a.test' }), 'available');
  assert.equal(websiteStatusOf({ name: 'x', websiteStatus: 'missing' }), 'missing');
});

test('a business that is also a 1-star review lead is linked to it, in the same record', async () => {
  const d = deps();
  const b = biz('Both');
  await recordCityWebsites([b, biz('Only Site Less')], { ...d.opts, reviewLeads: [{ mapsUrl: `${b.mapsUrl}?hl=en` }] });
  assert.deepEqual(d.saved.find((s) => s.business === 'Both').leadTypes, ['review']);
  assert.deepEqual(d.saved.find((s) => s.business === 'Only Site Less').leadTypes, []);
});

test('phones are normalised like review leads', () => {
  const { missing } = classifyBusinesses([biz('P')], { state: 'Texas' });
  assert.equal(missing[0].phone, '+15125550100');
  assert.match(missing[0].waLink, /wa\.me\/15125550100/);
  assert.equal(missing[0].location, 'Texas');
});

test('failures are contained: saving, flagging and queueing can all fail without throwing', async () => {
  const d = deps({
    saveWebsiteLeadsFn: async () => { throw new Error('firestore down'); },
    recordUnknownFn: async () => { throw new Error('firestore down'); },
    queue: { enqueue: () => { throw new Error('queue broke'); } },
  });
  const warnings = [];
  const original = console.warn;
  console.warn = (m) => warnings.push(m);
  try {
    await assert.doesNotReject(
      recordCityWebsites(
        [biz('A'), biz('B', { websiteStatus: 'unknown' }), biz('C', { website: 'https://c.test', websiteStatus: 'available' })],
        d.opts
      )
    );
  } finally {
    console.warn = original;
  }
  assert.ok(warnings.some((m) => /could not save/.test(m)));
  assert.ok(warnings.some((m) => /website processing failed/.test(m)));
});

test('with storage unavailable the pipeline does nothing at all', async () => {
  const d = deps({ enabled: false });
  const summary = await recordCityWebsites([biz('A'), biz('B', { website: 'https://b.test', websiteStatus: 'available' })], d.opts);
  assert.deepEqual(d.saved, []);
  assert.deepEqual(d.queued, []);
  assert.equal(summary.missing, 0);
});

// ---- the review scan is untouched by website / email processing ---------------

const oneStar = (name, extra = {}) => ({
  ...biz(name, extra),
  reviews: [{ stars: 1, reviewer: 'Sam', date: '2 days ago', text: 'bad', link: null }],
  reviewAccess: { complete: true, status: 'ok', sorted: true },
});

function scanJob(scrapeLocationFn, extra = {}) {
  return {
    concurrency: 2,
    dateRange: '28',
    maxResultsPerCity: 10,
    analyze: false,
    browser: null,
    cancelled: false,
    paused: false,
    requireSignIn: true,
    stoppedReason: null,
    scrapeLocationFn,
    seenPlaces: { Plumber: new Set() },
    activityLog: [],
    ...extra,
  };
}

test('website/email processing that throws does not disturb 1-star review results', async () => {
  const job = scanJob(async (_c, location) => [oneStar(`Plumb ${location}`)], {
    recordCityWebsitesFn: async () => {
      throw new Error('website pipeline exploded');
    },
  });
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  await scanStateCities(job, 'Plumber', rec);
  assert.equal(rec.status, 'done', 'every city still counts as covered');
  assert.equal(rec.failed.length, 0, 'no city is retried or failed because of it');
  assert.equal(rec.leadsCollected, 2, 'review leads are all kept');
  assert.ok(job.activityLog.some((l) => l.level === 'warn' && /website\/email processing failed/.test(l.message)));
});

test("the scan hands the pipeline each opened business (reviews stripped) and the city's review leads", async () => {
  const seen = [];
  const job = scanJob(async (_c, location) => [oneStar(`Plumb ${location}`), biz(`NoSite ${location}`)], {
    recordCityWebsitesFn: async (businesses, ctx) => seen.push({ businesses, ctx }),
  });
  const rec = newStateRecord('Texas', ['Austin']);
  await scanStateCities(job, 'Plumber', rec);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].businesses.length, 2);
  assert.ok(seen[0].businesses.every((b) => b.reviews === undefined && b.reviewAccess === undefined));
  assert.equal(seen[0].ctx.state, 'Texas');
  assert.equal(seen[0].ctx.reviewLeads.length, 1, 'only the 1-star business is a review lead');
  assert.equal(rec.leadsCollected, 1, 'a no-website business is not a review lead');
});
