import 'date_format.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime _day(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Whole calendar days from [date] to [now], in local time (0 = same day).
int daysAgo(DateTime date, {DateTime? now}) {
  final today = _day(now ?? DateTime.now());
  return today.difference(_day(date)).inDays;
}

/// Section title for a day: "Today", "Yesterday", "Mon, Oct 12" within the
/// last week, then "Oct 3, 2026". [date] null = "Earlier".
String dayLabel(DateTime? date, {DateTime? now}) {
  if (date == null) return 'Earlier';
  final ago = daysAgo(date, now: now);
  if (ago <= 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  final local = date.toLocal();
  if (ago < 7) return '${_weekdays[local.weekday - 1]}, ${_months[local.month - 1]} ${local.day}';
  return formatDate(date)!;
}

/// One row of a date-grouped list: a section [header], or an [item].
class DateGroupRow<T> {
  const DateGroupRow.header(String this.header) : item = null;
  const DateGroupRow.item(T this.item) : header = null;

  final String? header;
  final T? item;
}

/// Interleaves a header before each run of items that fall on the same local
/// day. [items] must already be in date order (newest first); a day that
/// appears again later simply gets another header.
List<DateGroupRow<T>> groupByDay<T>(List<T> items, DateTime? Function(T item) dateOf, {DateTime? now}) {
  final rows = <DateGroupRow<T>>[];
  String? current;
  for (final item in items) {
    final label = dayLabel(dateOf(item), now: now);
    if (label != current) {
      rows.add(DateGroupRow<T>.header(label));
      current = label;
    }
    rows.add(DateGroupRow<T>.item(item));
  }
  return rows;
}
