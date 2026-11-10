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

// ── no-website scan mode ─────────────────────────────────────────────────

test('a no-website scan never queues the sites of other businesses for email lookup', async () => {
  const d = deps({ queueEmails: false });
  const summary = await recordCityWebsites(
    [biz('No Site'), biz('Has Site', { website: 'https://hassite.test', websiteStatus: 'available' })],
    d.opts
  );
  assert.deepEqual(d.saved.map((s) => s.business), ['No Site']);
  assert.deepEqual(d.queued, [], 'the business with a website is excluded, not crawled');
  assert.equal(summary.available, 1);
  assert.equal(summary.queued, 0);
});

test('no-website mode: listings are read without reviews, and only confirmed no-website businesses count as leads', async () => {
  const calls = [];
  const filed = [];
  const job = scanJob(
    async (_c, location, options) => {
      calls.push(options);
      // A real no-website scan returns businesses with no reviews at all.
      return [
        { ...biz(`NoSite ${location}`), reviews: [] },
        { ...biz(`HasSite ${location}`, { website: 'https://x.test', websiteStatus: 'available' }), reviews: [] },
        { ...biz(`Unclear ${location}`, { websiteStatus: 'unknown' }), reviews: [] },
      ];
    },
    {
      mode: 'no_website',
      recordCityWebsitesFn: async (businesses, ctx) => {
        filed.push(ctx);
        // Mirror the real pipeline's summary: only `missing` are leads.
        return { missing: businesses.filter((b) => b.websiteStatus === 'missing').length };
      },
    }
  );
  const rec = newStateRecord('Texas', ['Austin', 'Dallas']);
  await scanStateCities(job, 'Plumber', rec);

  assert.equal(calls.length, 2, 'both cities were searched');
  assert.ok(calls.every((o) => o.skipReviews === true), 'the scraper was told not to read reviews');
  assert.equal(rec.status, 'done');
  assert.equal(rec.leadsCollected, 2, 'one confirmed no-website business per city; "has website" and "unclear" are not leads');
  assert.ok(filed.every((c) => c.queueEmails === false));
  assert.equal(rec.incompleteBusinesses, 0, 'no reviews were expected, so none are "not fully read"');
});

test('the review scan is unchanged: it still queues emails and counts only 1-star leads', async () => {
  const filed = [];
  const job = scanJob(async (_c, location) => [oneStar(`Plumb ${location}`), biz(`NoSite ${location}`)], {
    recordCityWebsitesFn: async (_b, ctx) => {
      filed.push(ctx);
      return { missing: 1 };
    },
  });
  const rec = newStateRecord('Texas', ['Austin']);
  await scanStateCities(job, 'Plumber', rec);
  assert.equal(filed[0].queueEmails, true);
  assert.equal(rec.leadsCollected, 1, 'the no-website business is not added to the review count');
});
