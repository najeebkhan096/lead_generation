import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/services/daily_contact_repository.dart';

void main() {
  group('dailyDayKey', () {
    test('the day turns over at midnight in Dubai (UTC+4), not UTC', () {
      expect(dailyDayKey(DateTime.utc(2026, 10, 18, 19, 59)), '2026-10-18');
      expect(dailyDayKey(DateTime.utc(2026, 10, 18, 20, 0)), '2026-10-19');
    });

    test('a day starts at midnight in Dubai, which is 20:00 UTC the day before', () {
      expect(dailyDayStart('2026-10-19'), DateTime.utc(2026, 10, 18, 20));
    });

    test('pads month and day', () {
      expect(dailyDayKey(DateTime.utc(2026, 1, 2, 12)), '2026-01-02');
    });
  });

  group('DailyContactStatus', () {
    test('reached at the limit, with nothing left', () {
      const status = DailyContactStatus(used: 10, limit: 10);
      expect(status.reached, isTrue);
      expect(status.left, 0);
    });

    test('counts what is left below the limit', () {
      const status = DailyContactStatus(used: 3, limit: 10);
      expect(status.reached, isFalse);
      expect(status.left, 7);
    });
  });
}
