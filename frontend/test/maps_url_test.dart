import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/utils/maps_url.dart';

void main() {
  test('accepts Google Maps links and adds a missing scheme', () {
    expect(normalizeMapsUrl('maps.app.goo.gl/JfuBDmWhBVb4ARTy7'), 'https://maps.app.goo.gl/JfuBDmWhBVb4ARTy7');
    expect(normalizeMapsUrl('https://goo.gl/maps/J8qEwq4JSYnRDbTBA'), 'https://goo.gl/maps/J8qEwq4JSYnRDbTBA');
  });

  test('rejects junk and non-Google links', () {
    for (final bad in ['dafaf', '', '  ', null, 'https://example.com/maps', 'https://google.com']) {
      expect(normalizeMapsUrl(bad), isNull, reason: '$bad');
    }
  });
}
