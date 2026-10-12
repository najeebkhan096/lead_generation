import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  discoverEmailsByWebSearch,
  pageMatchesBusiness,
  looksLikeOwnSite,
  cityFromAddress,
  phoneDigits,
  SearchBlockedError,
} from './webSearchEmailDiscovery.js';
import {
  startEmailValidationJob,
  getEmailJobSnapshot,
  _resetEmailValidationJobForTests,
} from './emailValidationJob.js';

const lead = {
  business: "Joe's Pizza",
  address: '12 Main St, Austin, TX 78701',
  location: 'TX',
  phone: '+1 512-555-0142',
};

const page = (html) => ({ ok: true, status: 200, html, finalUrl: '' });

function deps({ results, pages, crawl }) {
  return {
    searchFn: async () => results,
    fetchPageFn: async (url) => pages[url] || { ok: false, status: 404, html: '' },
    crawlFn: crawl || (async () => ({ emails: [], pagesFetched: 0 })),
  };
}

test('phone and city helpers', () => {
  assert.equal(phoneDigits('+1 (512) 555-0142'), '5125550142');
  assert.equal(phoneDigits('555-0142'), '');
  assert.equal(cityFromAddress('12 Main St, Austin, TX 78701'), 'Austin');
});

test('pageMatchesBusiness: phone is decisive; otherwise full name AND city', () => {
  assert.equal(pageMatchesBusiness('Call us (512) 555-0142 today', lead), true);
  assert.equal(pageMatchesBusiness('Call (512) 555-9999', lead), false);
  const noPhone = { business: "Joe's Pizza", address: '12 Main St, Austin, TX' };
  assert.equal(pageMatchesBusiness("Joe's Pizza in Austin serves slices", noPhone), true);
  assert.equal(pageMatchesBusiness("Joe's Pizza in Dallas", noPhone), false);
  assert.equal(pageMatchesBusiness('Pizza in Austin', noPhone), false);
});

test('looksLikeOwnSite uses the hostname, never an aggregator', () => {
  assert.equal(looksLikeOwnSite('joespizzatx.com', "Joe's Pizza"), true);
  assert.equal(looksLikeOwnSite('yelp.com', "Joe's Pizza"), false);
  assert.equal(looksLikeOwnSite('randomblog.com', "Joe's Pizza"), false);
});

test('keeps an address from a page that shows this business’s phone', async () => {
  const out = await discoverEmailsByWebSearch(
    lead,
    deps({
      results: ['https://austinlocal.example/joes'],
      pages: {
        'https://austinlocal.example/joes': page(
          "<p>Joe's Pizza (512) 555-0142</p><a href='mailto:orders@joespizzatx.com'>mail</a>"
        ),
      },
    })
  );
  assert.equal(out.primary, 'orders@joespizzatx.com');
  assert.equal(out.emailSource, 'web_search');
  assert.equal(out.foundOn, 'https://austinlocal.example/joes');
});

test('ignores pages that do not show the phone, aggregators, and directory dumps', async () => {
  const out = await discoverEmailsByWebSearch(
    lead,
    deps({
      results: [
        'https://wrongplace.example/a', // different business
        'https://www.yelp.com/biz/joes', // aggregator, even though phone matches
        'https://directory.example/pizza', // many addresses => directory
        'https://www.facebook.com/joespizza', // never fetched
      ],
      pages: {
        'https://wrongplace.example/a': page('Phone (512) 555-9999 <a href="mailto:x@other.example">x</a>'),
        'https://www.yelp.com/biz/joes': page('(512) 555-0142 <a href="mailto:support@yelp.com">s</a>'),
        'https://directory.example/pizza': page(
          '(512) 555-0142 a@one.example b@two.example c@three.example d@four.example'
        ),
        'https://www.facebook.com/joespizza': page('(512) 555-0142 fb@joes.example'),
      },
    })
  );
  assert.equal(out.primary, null);
  assert.equal(out.emails.length, 0);
  assert.match(out.lastError, /No email found/);
});

test('crawls the business’s own site once identified and prefers its addresses', async () => {
  let crawled = null;
  const out = await discoverEmailsByWebSearch(
    lead,
    deps({
      results: ['https://www.joespizzatx.com/about-us', 'https://austinlocal.example/joes'],
      pages: {
        'https://www.joespizzatx.com/about-us': page('Joe\'s Pizza (512) 555-0142'),
        'https://austinlocal.example/joes': page(
          '(512) 555-0142 <a href="mailto:random@austinlocal.example">r</a>'
        ),
      },
      crawl: async (origin) => {
        crawled = origin;
        return {
          emails: [{ email: 'info@joespizzatx.com', source: 'contact_page', score: 60 }],
          pagesFetched: 2,
        };
      },
    })
  );
  assert.equal(crawled, 'https://www.joespizzatx.com');
  assert.equal(out.website, 'https://www.joespizzatx.com');
  assert.equal(out.primary, 'info@joespizzatx.com');
  assert.equal(out.emailSource, 'contact_page');
  assert.ok(out.emails.some((e) => e.email === 'random@austinlocal.example'));
});

test('a blocked search surfaces as SearchBlockedError', async () => {
  await assert.rejects(
    discoverEmailsByWebSearch(lead, {
      searchFn: async () => {
        throw new SearchBlockedError();
      },
    }),
    (err) => err.code === 'SEARCH_BLOCKED'
  );
});

beforeEach(() => _resetEmailValidationJobForTests());

async function untilDone() {
  while (getEmailJobSnapshot()?.status === 'running') await new Promise((r) => setTimeout(r, 5));
  return getEmailJobSnapshot();
}

test('job (no-website mode) validates leads that have no website and saves provenance', async () => {
  const saved = [];
  startEmailValidationJob({
    recordCheckFn: async () => {}, // never touch the real leadChecks collection
    leads: [{ id: 'w1', dbId: 'w1', business: "Joe's Pizza", website: null, mapsUrl: 'm1' }],
    requireWebsite: false,
    discoverFn: async () => ({
      emails: [{ email: 'orders@joespizzatx.com', source: 'web_search', score: 20, foundOn: 'https://x.example/p' }],
      primary: 'orders@joespizzatx.com',
      emailSource: 'web_search',
      foundOn: 'https://x.example/p',
      website: null,
      pagesFetched: 1,
      searched: true,
    }),
    verifyFn: async () => ({ result: 'valid', reason: 'mx_found' }),
    saveFn: async (l) => saved.push(...l),
  });
  const snap = await untilDone();
  assert.equal(snap.validCount, 1);
  assert.equal(snap.results.w1.foundOn, 'https://x.example/p');
  assert.equal(saved[0].emailFoundOn, 'https://x.example/p');
  assert.equal(saved[0].emailSource, 'web_search');
  assert.equal(saved[0].dbId, 'w1');
});

test('job halts (without counting the refused lookup) when the search engine blocks', async () => {
  let calls = 0;
  startEmailValidationJob({
    recordCheckFn: async () => {}, // never touch the real leadChecks collection
    leads: Array.from({ length: 8 }, (_, i) => ({ id: `w${i}`, business: `Biz ${i}`, mapsUrl: `m${i}` })),
    requireWebsite: false,
    concurrency: 1,
    discoverFn: async () => {
      calls += 1;
      if (calls === 3) throw new SearchBlockedError();
      return { emails: [], primary: null, pagesFetched: 1, searched: true };
    },
    verifyFn: async () => ({ result: 'valid' }),
    saveFn: async () => {},
  });
  const snap = await untilDone();
  assert.equal(calls, 3);
  assert.equal(snap.checked, 2);
  assert.equal(snap.noEmailCount, 2);
  assert.match(snap.stoppedReason, /rate-limiting/);
});
