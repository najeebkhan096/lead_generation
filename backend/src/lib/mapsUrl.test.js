import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeMapsUrl, clientNameKey } from './mapsUrl.js';

test('accepts Google Maps links, adding a missing scheme', () => {
  assert.equal(normalizeMapsUrl('maps.app.goo.gl/JfuBDmWhBVb4ARTy7'), 'https://maps.app.goo.gl/JfuBDmWhBVb4ARTy7');
  assert.equal(normalizeMapsUrl('https://goo.gl/maps/J8qEwq4JSYnRDbTBA'), 'https://goo.gl/maps/J8qEwq4JSYnRDbTBA');
  assert.equal(normalizeMapsUrl('  https://www.google.com/maps/place/Foo+Bar/@1,2,17z  '), 'https://www.google.com/maps/place/Foo+Bar/@1,2,17z');
  assert.equal(normalizeMapsUrl('https://g.page/r/abc/review'), 'https://g.page/r/abc/review');
  assert.equal(normalizeMapsUrl('https://www.google.co.uk/maps?q=x'), 'https://www.google.co.uk/maps?q=x');
});

test('keeps the query string intact', () => {
  assert.equal(
    normalizeMapsUrl('https://maps.app.goo.gl/rtPHmxKedCrf59nj9?g_st=ic'),
    'https://maps.app.goo.gl/rtPHmxKedCrf59nj9?g_st=ic',
  );
});

test('rejects junk, non-Google links and bare homepages', () => {
  for (const bad of ['dafaf', 'ahha', 'jdjdjd', '', '   ', null, undefined, 'two words.com', 'https://example.com/maps', 'https://google.com', 'ftp://goo.gl/x', 'notgoogle.com/maps', 'evilgoogle.com/maps']) {
    assert.equal(normalizeMapsUrl(bad), null, String(bad));
  }
});

test('name key ignores case and spacing', () => {
  assert.equal(clientNameKey('  Titan  Collision center '), clientNameKey('Titan Collision Center'));
  assert.notEqual(clientNameKey('Triple garage'), clientNameKey('Triiple a Garage'));
});
