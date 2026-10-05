import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeEmail,
  extractEmailsFromHtml,
  pickBestEmail,
  scoreEmail,
  originFromWebsite,
} from './emailDiscoveryService.js';
import { classifySyntax } from './emailVerificationService.js';
import { analyzeHtml } from './websiteAnalysisService.js';
import { buildTemplateEmail } from './aiEmailGeneratorService.js';
import { isTemporarySendFailure } from './emailSenderService.js';
import { leadMatchesFilters } from './outreachStore.js';
import { parseLeadRange } from './constants.js';

test('normalizeEmail rejects placeholders and keeps business addresses', () => {
  assert.equal(normalizeEmail('Info@Cafe.example.com'), 'info@cafe.example.com');
  assert.equal(normalizeEmail('mailto:info@abcrestaurant.com?subject=Hi'), 'info@abcrestaurant.com');
  assert.equal(normalizeEmail('user@example.com'), null);
  assert.equal(normalizeEmail('not-an-email'), null);
});

test('extractEmailsFromHtml finds mailto and visible addresses', () => {
  const html = `
    <a href="mailto:contact@abcrestaurant.com">Email us</a>
    <p>Also hello@abcrestaurant.com</p>
    <img src="file@cdn.google.com">
  `;
  const found = extractEmailsFromHtml(html).map((f) => f.email);
  assert.ok(found.includes('contact@abcrestaurant.com'));
  assert.ok(found.includes('hello@abcrestaurant.com'));
});

test('pickBestEmail prefers info@ on the business domain', () => {
  const { best } = pickBestEmail([
    { email: 'john.smith@gmail.com', via: 'text', source: 'website' },
    { email: 'info@abcrestaurant.com', via: 'mailto', source: 'contact_page' },
  ], 'abcrestaurant.com');
  assert.equal(best.email, 'info@abcrestaurant.com');
  assert.ok(scoreEmail('info@abcrestaurant.com', 'abcrestaurant.com') > scoreEmail('person@gmail.com', 'abcrestaurant.com'));
});

test('originFromWebsite requires a real host', () => {
  assert.equal(originFromWebsite('abcrestaurant.com'), 'https://abcrestaurant.com');
  assert.equal(originFromWebsite('https://abcrestaurant.com/menu'), 'https://abcrestaurant.com');
  assert.equal(originFromWebsite(''), null);
});

test('classifySyntax flags disposable domains', () => {
  const disposable = classifySyntax('a@mailinator.com');
  assert.equal(disposable.ok, false);
  assert.equal(disposable.reason, 'disposable');
  assert.equal(classifySyntax('info@abcrestaurant.com').ok, true);
});

test('analyzeHtml only reports issues with evidence', () => {
  const html = '<html><head></head><body><p>Welcome</p></body></html>';
  const result = analyzeHtml({ html, bytes: 100, elapsedMs: 20, finalUrl: 'http://x.test/', status: 200 });
  assert.ok(result.issues.some((i) => i.title.includes('viewport')));
  assert.ok(result.issues.every((i) => i.evidence));
  assert.ok(result.score < 90);
});

test('template email does not invent website problems', () => {
  const { subject, body } = buildTemplateEmail({
    business: 'ABC Restaurant',
    category: 'restaurants',
    location: 'Doha',
    analysis: { score: 18, issues: [], opportunities: [], signals: { hasWebsite: false } },
    senderName: 'Najeeb',
  });
  assert.match(subject, /ABC Restaurant/);
  assert.match(body, /does not currently show a website/);
  assert.doesNotMatch(body, /booking system is broken/i);
  assert.match(body, /Najeeb/);
});

test('temporary send failures retry', () => {
  assert.equal(isTemporarySendFailure({ status: 429 }), true);
  assert.equal(isTemporarySendFailure({ message: 'ETIMEDOUT' }), true);
  assert.equal(isTemporarySendFailure({ status: 400, message: 'invalid recipient' }), false);
});

test('campaign filters match website-lead fields', () => {
  const lead = { category: 'restaurants Qatar', location: 'Doha', website: null, email: null };
  assert.equal(leadMatchesFilters(lead, { category: 'restaurants Qatar' }), true);
  assert.equal(leadMatchesFilters(lead, { location: 'doha' }), true);
  assert.equal(leadMatchesFilters(lead, { hasWebsite: true }), false);
  assert.equal(leadMatchesFilters(lead, { hasWebsite: false }), true);
});

test('parseLeadRange accepts a small from/to window', () => {
  assert.deepEqual(parseLeadRange(1, 20), { from: 1, to: 20, count: 20 });
  assert.deepEqual(parseLeadRange('5', '5'), { from: 5, to: 5, count: 1 });
  assert.equal(parseLeadRange(10, 3).from, 10);
});

test('parseLeadRange rejects more than 200 leads', () => {
  assert.throws(() => parseLeadRange(1, 201), /at most 200/);
});
