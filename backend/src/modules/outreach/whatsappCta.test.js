import { test } from 'node:test';
import assert from 'node:assert/strict';
import { appendWhatsAppCta, businessFromPrefill, whatsappChatUrl, whatsappDigits } from './whatsappCta.js';

test('whatsappDigits accepts E.164 in any common spelling and rejects junk', () => {
  assert.equal(whatsappDigits('+1 (415) 555-0100'), '14155550100');
  assert.equal(whatsappDigits('whatsapp:+14155550100'), '14155550100');
  assert.equal(whatsappDigits(''), '');
  assert.equal(whatsappDigits('12345'), '');
  assert.equal(whatsappDigits(undefined), '');
});

test('chat link names the business in the prefilled text', () => {
  const url = whatsappChatUrl('+14155550100', "Joe's Cafe & Bar");
  assert.ok(url.startsWith('https://wa.me/14155550100?text='));
  assert.equal(
    decodeURIComponent(url.split('text=')[1]),
    "Hi, I got your email about Joe's Cafe & Bar.",
  );
  assert.equal(whatsappChatUrl('', 'X'), '');
});

test('the business name survives the round trip through the prefilled text', () => {
  const url = whatsappChatUrl('+14155550100', 'Acme Plumbing');
  assert.equal(businessFromPrefill(decodeURIComponent(url.split('text=')[1])), 'Acme Plumbing');
  assert.equal(businessFromPrefill('hello'), '');
  assert.equal(businessFromPrefill(''), '');
});

test('appendWhatsAppCta adds the link once and respects the switch', () => {
  const opts = { number: '+14155550100', business: 'Acme' };
  const once = appendWhatsAppCta('Hello\n\nBest,\nNajeeb', opts);
  assert.match(once, /Prefer WhatsApp\?/);
  assert.match(once, /https:\/\/wa\.me\/14155550100\?text=/);
  assert.equal(appendWhatsAppCta(once, opts), once);
  assert.equal(appendWhatsAppCta('Hello', { ...opts, enabled: false }), 'Hello');
  assert.equal(appendWhatsAppCta('Hello', { number: '', business: 'Acme' }), 'Hello');
});
