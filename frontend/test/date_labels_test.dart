import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/utils/date_labels.dart';

void main() {
  test('a day reads like 20 Oct', () {
    expect(dayLabel('2026-10-20'), '20 Oct');
    expect(dayLabel('2026-01-05'), '5 Jan');
    expect(dayLabel('not a day'), 'not a day');
    expect(dayLabel('2026-13-01'), '2026-13-01');
  });

  test('a date and time read like 20 Oct 14:05', () {
    expect(dateLabel(DateTime(2026, 10, 20, 14, 5)), '20 Oct');
    expect(dateTimeLabel(DateTime(2026, 10, 20, 14, 5)), '20 Oct 14:05');
    expect(dateTimeLabel(DateTime(2026, 3, 9, 7, 0)), '9 Mar 07:00');
  });
}
