import test from 'node:test';
import assert from 'node:assert/strict';
import { computeTwilioSignature, isValidTwilioSignature } from './signature.js';
import {
  HttpError, isValidE164, isWindowOpen, leadIdFor, mapTwilioStatus, messageTypeForMime, nextStatus, normalizePhone,
  previewFor, validateMediaMeta,
} from './validation.js';
import { templateMediaVariable, validateReaction } from './messageService.js';

test('phone normalisation + E.164', () => {
  assert.equal(normalizePhone('whatsapp:+971 50-123 (4567)'), '+971501234567');
  assert.equal(normalizePhone('+٩٧١٥٠١٢٣٤٥٦٧'), '+971501234567');
  assert.ok(isValidE164('+971501234567'));
  assert.ok(!isValidE164('0501234567'));
  assert.equal(leadIdFor('uid1', '+971501234567'), 'uid1_971501234567');
});

test('status lifecycle ignores duplicates and out-of-order callbacks', () => {
  assert.equal(nextStatus('sending', 'sent'), 'sent');
  assert.equal(nextStatus('sent', 'sent'), null);
  assert.equal(nextStatus('delivered', 'sent'), null);
  assert.equal(nextStatus('sent', 'read'), 'read');
  assert.equal(nextStatus('read', 'delivered'), null);
  assert.equal(nextStatus('sent', 'undelivered'), 'undelivered');
  assert.equal(nextStatus('delivered', 'failed'), null);
  assert.equal(nextStatus('failed', 'undelivered'), null);
  assert.equal(nextStatus('sending', mapTwilioStatus('queued')), null);
  assert.equal(mapTwilioStatus('weird'), null);
});

test('media validation: type, extension, size', () => {
  assert.deepEqual(validateMediaMeta({ mimeType: 'image/jpeg', fileName: 'a.JPG', size: 100 }), { mime: 'image/jpeg', type: 'image' });
  assert.throws(() => validateMediaMeta({ mimeType: 'application/zip', fileName: 'a.zip', size: 1 }), (e) => e.code === 'UNSUPPORTED_MEDIA');
  assert.throws(() => validateMediaMeta({ mimeType: 'application/pdf', fileName: 'a.exe', size: 1 }), (e) => e.code === 'EXTENSION_MISMATCH');
  assert.throws(() => validateMediaMeta({ mimeType: 'video/mp4', fileName: 'a.mp4', size: 17 * 1024 * 1024 }), (e) => e.code === 'MEDIA_TOO_LARGE');
  assert.equal(messageTypeForMime('audio/ogg; codecs=opus'), 'audio');
  assert.equal(previewFor('image', ''), '📷 Photo');
});

test('24h window', () => {
  const now = 1_000_000_000_000;
  assert.ok(isWindowOpen(now - 3600_000, now));
  assert.ok(!isWindowOpen(now - 25 * 3600_000, now));
  assert.ok(!isWindowOpen(null, now));
});

test('Twilio signature round-trip', () => {
  const params = { From: 'whatsapp:+1', Body: 'hi', MessageSid: 'SM1' };
  const url = 'https://x.example/api/twilio/webhooks/incoming';
  const sig = computeTwilioSignature('tok', url, params);
  assert.ok(isValidTwilioSignature('tok', sig, url, params));
  assert.ok(!isValidTwilioSignature('tok', sig, url, { ...params, Body: 'tampered' }));
  assert.ok(!isValidTwilioSignature('tok', undefined, url, params));
});

test('Twilio signature matches the published Twilio example vector', () => {
  // https://www.twilio.com/docs/usage/security#validating-requests
  const params = { CallSid: 'CA1234567890ABCDE', Caller: '+14158675310', Digits: '1234', From: '+14158675310', To: '+18005551212' };
  assert.equal(
    computeTwilioSignature('12345', 'https://mycompany.com/myapp.php?foo=1&bar=2', params),
    'GvWf1cFY/Q7PnoempGyD5oXAezc=',
  );
});

test('template media variable keeps the "after /o/" contract and enforces ownership', () => {
  const prefix = 'https://firebasestorage.googleapis.com/v0/b/b/o/';
  const v = 'outreach_images%2Fu1%2F1.jpg?alt=media&token=t';
  assert.equal(templateMediaVariable('u1', prefix + v, prefix), v);
  assert.throws(() => templateMediaVariable('u2', prefix + v, prefix), (e) => e instanceof HttpError && e.status === 403);
  assert.throws(() => templateMediaVariable('u1', 'https://evil.example/x.jpg', prefix), (e) => e.status === 400);
});

test('reaction validation accepts one emoji (incl. ZWJ / skin tones) and removal, rejects text', () => {
  assert.equal(validateReaction('👍'), '👍');
  assert.equal(validateReaction('👍🏽'), '👍🏽');
  assert.equal(validateReaction('👨‍👩‍👧'), '👨‍👩‍👧');
  assert.equal(validateReaction(null), null);
  assert.equal(validateReaction(''), null);
  for (const bad of ['a', 'hi 👍', '<script>', '12', '👍'.repeat(20)]) {
    assert.throws(() => validateReaction(bad), (e) => e.code === 'BAD_REACTION', bad);
  }
});
