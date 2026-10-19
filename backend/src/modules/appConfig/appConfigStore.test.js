import { test } from 'node:test';
import assert from 'node:assert/strict';
import { looksLikeApk, validateRule } from './appConfigStore.js';

test('a rule needs whole-number builds, with latest at or above the minimum', () => {
  assert.deepEqual(validateRule({ minBuild: 2, latestBuild: 3, message: '  Update now  ' }), { minBuild: 2, latestBuild: 3, message: 'Update now' });
  assert.throws(() => validateRule({ minBuild: 2.5, latestBuild: 3 }), (err) => err.status === 400);
  assert.throws(() => validateRule({ minBuild: -1, latestBuild: 3 }), (err) => err.status === 400);
  assert.throws(() => validateRule({ minBuild: 4, latestBuild: 3 }), (err) => err.status === 400 && /lower than minBuild/.test(err.message));
});

test('the message is optional, but limited in length', () => {
  assert.equal(validateRule({ minBuild: 1, latestBuild: 1 }).message, '');
  assert.throws(() => validateRule({ minBuild: 1, latestBuild: 1, message: 'x'.repeat(301) }), (err) => err.status === 400);
});

test('only a real APK is accepted: a zip archive of a sensible size', () => {
  const apk = Buffer.alloc(2 * 1024 * 1024);
  apk.write('PK', 0, 'ascii');
  assert.equal(looksLikeApk(apk), true);
  assert.equal(looksLikeApk(Buffer.from('PK tiny')), false, 'too small to be an app');
  const notZip = Buffer.alloc(2 * 1024 * 1024);
  assert.equal(looksLikeApk(notZip), false, 'not a zip archive');
  assert.equal(looksLikeApk(null), false);
});
