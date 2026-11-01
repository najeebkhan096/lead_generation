import { test } from 'node:test';
import assert from 'node:assert/strict';
import { crawlSiteForEmails, normalizeWebsiteUrl, parseRobots, isRetryableReason } from './websiteFetcher.js';

const noSleep = async () => {};

/** A fake `fetch` over a map of url -> {status, body, headers} | Error. Records every URL asked for. */
function fakeFetch(routes) {
  const calls = [];
  const fn = async (url) => {
    calls.push(String(url));
    const route = routes[String(url)];
    if (route === undefined) return new Response('not here', { status: 404, headers: { 'content-type': 'text/html' } });
    if (route instanceof Error) throw route;
    return new Response(route.body ?? '', {
      status: route.status ?? 200,
      headers: { 'content-type': 'text/html', ...(route.headers || {}) },
    });
  };
  fn.calls = calls;
  return fn;
}

const page = (body) => `<html><body>${body}${'<p>Plenty of ordinary page text for the shop.</p>'.repeat(60)}</body></html>`;
const timeoutError = () => Object.assign(new Error('timed out'), { name: 'TimeoutError' });

test('a website that publishes an email: found, with the page it came from', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/': { body: page('<a href="mailto:hello@shop.test">Email</a>') },
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'found');
  assert.deepEqual(r.emails, [{ address: 'hello@shop.test', sourceUrl: 'https://shop.test/' }]);
});

test('the contact page is read when the homepage has no address, and is named as the source', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/': { body: page('<a href="/contact">Contact</a>') },
    'https://shop.test/contact': { body: page('<p>Write to office@shop.test</p>') },
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'found');
  assert.deepEqual(r.emails, [{ address: 'office@shop.test', sourceUrl: 'https://shop.test/contact' }]);
  assert.equal(r.pagesChecked, 2);
});

test('multiple addresses are kept, own-domain first, each with its source', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/': { body: page('<a href="mailto:owner@gmail.com">Owner</a><a href="/contact">Contact</a>') },
    'https://shop.test/contact': { body: page('<p>sales@shop.test and support@shop.test</p>') },
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.deepEqual(r.emails.map((e) => e.address), ['sales@shop.test', 'support@shop.test', 'owner@gmail.com']);
  assert.equal(r.emails[2].sourceUrl, 'https://shop.test/');
});

test('a website with no published email: not_found (never invented)', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/': { body: page('<a href="/contact">Contact</a>') },
    'https://shop.test/contact': { body: page('<p>Use the form below.</p>') },
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'not_found');
  assert.deepEqual(r.emails, []);
});

test('a contact page that cannot be read means check_failed, not not_found', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/': { body: page('<a href="/contact">Contact</a>') },
    'https://shop.test/contact': timeoutError(),
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'check_failed');
  assert.equal(r.reason, 'timeout');
});

test('a timeout is retried once, then reported as check_failed/timeout', async () => {
  const fetchFn = fakeFetch({ 'https://shop.test/': timeoutError() });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'check_failed');
  assert.equal(r.reason, 'timeout');
  assert.equal(fetchFn.calls.filter((u) => u === 'https://shop.test/').length, 2, 'one retry');
  assert.equal(isRetryableReason(r.reason), true);
});

test('a blocked site (403) is not retried and not bypassed', async () => {
  const fetchFn = fakeFetch({ 'https://shop.test/': { status: 403, body: 'Forbidden' } });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'check_failed');
  assert.equal(r.reason, 'blocked');
  assert.equal(fetchFn.calls.filter((u) => u === 'https://shop.test/').length, 1);
  assert.equal(isRetryableReason(r.reason), false);
});

test('a CAPTCHA page is reported as blocked', async () => {
  const fetchFn = fakeFetch({ 'https://shop.test/': { body: '<html><title>Just a moment...</title><div class="cf-challenge"></div></html>' } });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'check_failed');
  assert.equal(r.reason, 'blocked');
});

test('robots.txt is respected: a disallowed site is not_checked and its page is never requested', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/robots.txt': { body: 'User-agent: *\nDisallow: /' },
    'https://shop.test/': { body: page('<a href="mailto:hello@shop.test">x</a>') },
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'not_checked');
  assert.equal(r.reason, 'robots_disallowed');
  assert.ok(!fetchFn.calls.includes('https://shop.test/'));
});

test('a contact page disallowed by robots.txt is skipped, the rest still read', async () => {
  const fetchFn = fakeFetch({
    'https://shop.test/robots.txt': { body: 'User-agent: *\nDisallow: /contact' },
    'https://shop.test/': { body: page('<a href="/contact">Contact</a><a href="/about">About</a>') },
    'https://shop.test/about': { body: page('<p>team@shop.test</p>') },
  });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'found');
  assert.ok(!fetchFn.calls.includes('https://shop.test/contact'));
});

test('a redirect to a private address is refused', async () => {
  const fetchFn = fakeFetch({ 'https://shop.test/': { status: 302, headers: { location: 'http://127.0.0.1/admin' } } });
  const r = await crawlSiteForEmails('https://shop.test/', { fetchFn, sleep: noSleep });
  assert.equal(r.status, 'check_failed');
  assert.equal(r.reason, 'unsafe_redirect');
  assert.ok(!fetchFn.calls.some((u) => u.includes('127.0.0.1')));
});

test('an unusable website value is not_checked, with no request at all', async () => {
  const fetchFn = fakeFetch({});
  for (const bad of ['', null, 'ftp://x.com', 'http://localhost/', 'http://192.168.1.5/', 'not a url']) {
    const r = await crawlSiteForEmails(bad, { fetchFn, sleep: noSleep });
    assert.equal(r.status, 'not_checked', String(bad));
  }
  assert.equal(fetchFn.calls.length, 0);
});

test('normalizeWebsiteUrl adds a scheme and unwraps Google redirect links', () => {
  assert.equal(normalizeWebsiteUrl('shop.test'), 'https://shop.test/');
  assert.equal(normalizeWebsiteUrl('https://www.google.com/url?q=https%3A%2F%2Fshop.test%2F&sa=U'), 'https://shop.test/');
  assert.equal(normalizeWebsiteUrl('https://user:pw@shop.test/'), null);
});

test('robots.txt: the longest matching rule wins, wildcards work', () => {
  const robots = parseRobots('User-agent: *\nDisallow: /private\nAllow: /private/open\nDisallow: /*.pdf$');
  assert.equal(robots.isAllowed('/private/x'), false);
  assert.equal(robots.isAllowed('/private/open/y'), true);
  assert.equal(robots.isAllowed('/a/b.pdf'), false);
  assert.equal(robots.isAllowed('/contact'), true);
  assert.equal(parseRobots('').isAllowed('/anything'), true);
});
