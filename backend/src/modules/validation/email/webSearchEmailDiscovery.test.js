import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  discoverEmailsByWebSearch,
  pageMatchesBusiness,
  looksLikeOwnSite,
  cityFromAddress,
  phoneDigits,
  SearchBlockedError,
} from './webSearchEmailDiscovery.js';

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
    crawlFn: crawl || (async () => ({ status: 'not_found', emails: [], pagesChecked: 0 })),
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
          status: 'found',
          emails: [{ address: 'info@joespizzatx.com', sourceUrl: 'https://www.joespizzatx.com/contact' }],
          pagesChecked: 2,
        };
      },
    })
  );
  assert.equal(crawled, 'https://www.joespizzatx.com');
  assert.equal(out.website, 'https://www.joespizzatx.com');
  assert.equal(out.primary, 'info@joespizzatx.com');
  assert.equal(out.emailSource, 'website');
  assert.equal(out.foundOn, 'https://www.joespizzatx.com/contact');
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
