import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/app_update_config.dart';

void main() {
  test('parses the stored rule, and reads a missing one as not set', () {
    final config = AppUpdateConfig.fromJson({
      'minBuild': 2,
      'latestBuild': 3,
      'apkUrl': 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=t',
      'message': 'Please update.',
      'updatedAt': '2026-10-19T12:00:00.000Z',
    });
    expect(config.minBuild, 2);
    expect(config.latestBuild, 3);
    expect(config.apkUrl, startsWith('https://'));
    expect(config.message, 'Please update.');
    expect(config.updatedAt, isNotNull);

    final empty = AppUpdateConfig.fromJson({});
    expect(empty.minBuild, 0);
    expect(empty.apkUrl, '');
    expect(empty.updatedAt, isNull);
  });
}
