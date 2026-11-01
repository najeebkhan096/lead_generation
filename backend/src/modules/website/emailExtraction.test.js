import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  extractEmailsFromHtml,
  normalizeEmail,
  isValidBusinessEmail,
  findContactPageLinks,
  looksLikeChallengePage,
  rankEmails,
  siteDomain,
} from './emailExtraction.js';

test('a mailto link and a visible address are both found, once each', () => {
  const html = `<html><body>
    <a href="mailto:Info@Joes-Plumbing.com?subject=Hello">Email us</a>
    <p>Or write to info@joes-plumbing.com or sales@joes-plumbing.com.</p>
  </body></html>`;
  assert.deepEqual(extractEmailsFromHtml(html), ['info@joes-plumbing.com', 'sales@joes-plumbing.com']);
});

test('several recipients in one mailto are all kept', () => {
  const html = '<a href="mailto:a@shop.com,b@shop.com">team</a>';
  assert.deepEqual(extractEmailsFromHtml(html), ['a@shop.com', 'b@shop.com']);
});

test('malformed, placeholder, file-name and no-reply addresses are discarded', () => {
  const html = `<body>
    <p>bad@ , @nope.com, two@@x.com, a..b@x.com, no-tld@localhost</p>
    <p>logo@2x.png, sprite@3x.webp, you@example.com, your@email.com, name@domain.com</p>
    <p>noreply@shop.com, do-not-reply@shop.com, error@sentry.io</p>
    <p>real@shop.com</p></body>`;
  assert.deepEqual(extractEmailsFromHtml(html), ['real@shop.com']);
});

test('addresses inside scripts and styles are ignored', () => {
  const html = '<script>var x="hidden@shop.com"</script><style>/* css@shop.com */</style><p>shown@shop.com</p>';
  assert.deepEqual(extractEmailsFromHtml(html), ['shown@shop.com']);
});

test("Cloudflare's data-cfemail encoding is decoded", () => {
  // "hi@shop.com" XOR-encoded with key 0x42
  const key = 0x42;
  const hex = [key, ...[...'hi@shop.com'].map((c) => c.charCodeAt(0) ^ key)].map((b) => b.toString(16).padStart(2, '0')).join('');
  assert.deepEqual(extractEmailsFromHtml(`<a class="__cf_email__" data-cfemail="${hex}">[email&#160;protected]</a>`), ['hi@shop.com']);
});

test('nothing is invented: a page without addresses yields none', () => {
  assert.deepEqual(extractEmailsFromHtml('<p>Call us on 555-0100. Visit our contact form.</p>'), []);
  assert.deepEqual(extractEmailsFromHtml(''), []);
  assert.deepEqual(extractEmailsFromHtml(null), []);
});

test('normalizeEmail and isValidBusinessEmail', () => {
  assert.equal(normalizeEmail(' MAILTO:Sales@Shop.COM?cc=x '), 'sales@shop.com');
  assert.equal(normalizeEmail('<info@shop.com>.'), 'info@shop.com');
  assert.equal(normalizeEmail(''), null);
  assert.equal(isValidBusinessEmail('a@b.co'), true);
  assert.equal(isValidBusinessEmail('a@b'), false);
  assert.equal(isValidBusinessEmail('a b@c.com'), false);
  assert.equal(isValidBusinessEmail(`${'x'.repeat(65)}@c.com`), false);
});

test("an address on the business's own domain ranks first", () => {
  assert.equal(siteDomain('www.joes.co.uk'), 'joes.co.uk');
  assert.deepEqual(rankEmails(['joe@gmail.com', 'info@joes.com'], 'www.joes.com'), ['info@joes.com', 'joe@gmail.com']);
});

test('contact-type pages on the same site are found; other hosts and files are not', () => {
  const html = `<nav>
    <a href="/about-us">About</a><a href="/contact">Contact</a><a href="/products">Products</a>
    <a href="https://other.com/contact">Partner</a><a href="/brochure-contact.pdf">PDF</a>
    <a href="mailto:x@y.com">mail</a><a href="#top">Top</a><a href="/">Home</a>
  </nav>`;
  assert.deepEqual(findContactPageLinks(html, 'https://www.shop.com/'), ['https://www.shop.com/contact', 'https://www.shop.com/about-us']);
});

test('a CAPTCHA page is recognised; a real page with a reCAPTCHA form is not', () => {
  assert.equal(looksLikeChallengePage('<html><title>Just a moment...</title><div class="cf-challenge"></div></html>'), true);
  const real = `<html><div class="g-recaptcha"></div>${'<p>Welcome to our shop and our services. </p>'.repeat(80)}</html>`;
  assert.equal(looksLikeChallengePage(real), false);
});

test('an address is not glued to the text of the element after it', () => {
  assert.deepEqual(extractEmailsFromHtml('<p>office@shop.com</p><p>Opening hours</p><li>sales@shop.com</li><li>Tuesday</li>'), [
    'office@shop.com',
    'sales@shop.com',
  ]);
});
