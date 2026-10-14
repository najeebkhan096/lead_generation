import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/utils/date_groups.dart';

void main() {
  // Wednesday 14 Oct 2026, mid-afternoon local time.
  final now = DateTime(2026, 10, 14, 15, 30);

  group('dayLabel', () {
    test('today, even just after midnight', () {
      expect(dayLabel(DateTime(2026, 10, 14, 0, 5), now: now), 'Today');
      expect(dayLabel(DateTime(2026, 10, 14, 15, 29), now: now), 'Today');
    });

    test('yesterday is the previous calendar day, not 24 hours ago', () {
      expect(dayLabel(DateTime(2026, 10, 13, 23, 59), now: now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 10, 13, 0, 1), now: now), 'Yesterday');
    });

    test('earlier this week shows the weekday and date', () {
      expect(dayLabel(DateTime(2026, 10, 12, 9), now: now), 'Mon, Oct 12');
      expect(dayLabel(DateTime(2026, 10, 8, 9), now: now), 'Thu, Oct 8');
    });

    test('a week or more ago shows the full date', () {
      expect(dayLabel(DateTime(2026, 10, 7, 9), now: now), 'Oct 7, 2026');
      expect(dayLabel(DateTime(2025, 12, 31), now: now), 'Dec 31, 2025');
    });

    test('a future or missing date is not mislabelled', () {
      expect(dayLabel(DateTime(2026, 10, 15, 1), now: now), 'Today');
      expect(dayLabel(null, now: now), 'Earlier');
    });

    test('works across a month boundary', () {
      final firstOfMonth = DateTime(2026, 11, 1, 10);
      expect(dayLabel(DateTime(2026, 10, 31, 22), now: firstOfMonth), 'Yesterday');
    });
  });

  group('groupByDay', () {
    DateTime? at(String s) => s.isEmpty ? null : DateTime.parse(s);

    test('puts one header before each run of the same day', () {
      final items = ['2026-10-14T10:00', '2026-10-14T08:00', '2026-10-13T20:00', '2026-10-01T09:00'];
      final rows = groupByDay<String>(items, at, now: now);
      expect(
        rows.map((r) => r.header ?? r.item).toList(),
        [
          'Today',
          '2026-10-14T10:00',
          '2026-10-14T08:00',
          'Yesterday',
          '2026-10-13T20:00',
          'Oct 1, 2026',
          '2026-10-01T09:00',
        ],
      );
    });

    test('no items, no headers', () {
      expect(groupByDay<String>(const [], at, now: now), isEmpty);
    });

    test('undated items are grouped under Earlier', () {
      final rows = groupByDay<String>(['', ''], at, now: now);
      expect(rows.map((r) => r.header ?? r.item).toList(), ['Earlier', '', '']);
    });
  });
}
