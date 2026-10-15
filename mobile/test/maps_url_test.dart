import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/utils/maps_url.dart';

void main() {
  test('accepts Google Maps links and adds a missing scheme', () {
    expect(normalizeMapsUrl('maps.app.goo.gl/JfuBDmWhBVb4ARTy7'), 'https://maps.app.goo.gl/JfuBDmWhBVb4ARTy7');
    expect(normalizeMapsUrl('https://goo.gl/maps/J8qEwq4JSYnRDbTBA'), 'https://goo.gl/maps/J8qEwq4JSYnRDbTBA');
    expect(normalizeMapsUrl('http://www.google.com/maps/place/Foo/@1,2,17z'), 'https://www.google.com/maps/place/Foo/@1,2,17z');
    expect(normalizeMapsUrl('https://g.page/r/abc/review'), 'https://g.page/r/abc/review');
    expect(normalizeMapsUrl('https://maps.app.goo.gl/rtPHmxKedCrf59nj9?g_st=ic'), 'https://maps.app.goo.gl/rtPHmxKedCrf59nj9?g_st=ic');
  });

  test('rejects junk, non-Google links and bare homepages', () {
    for (final bad in ['dafaf', 'ahha', '', '   ', null, 'two words.com', 'https://example.com/maps', 'https://google.com', 'evilgoogle.com/maps', 'notgoogle.com/maps']) {
      expect(normalizeMapsUrl(bad), isNull, reason: '$bad');
    }
  });

  test('name key ignores case and spacing', () {
    expect(clientNameKey('  Titan  Collision center '), clientNameKey('Titan Collision Center'));
  });
}
