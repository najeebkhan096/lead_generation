const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "20 Oct" for a local date.
String dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "20 Oct 14:05" for a local date and time.
String dateTimeLabel(DateTime d) => '${dateLabel(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// "20 Oct" for a 'YYYY-MM-DD' day key. Returns the key unchanged if it is not one.
String dayLabel(String day) {
  final parts = day.split('-');
  if (parts.length != 3) return day;
  final month = int.tryParse(parts[1]);
  final dayOfMonth = int.tryParse(parts[2]);
  if (month == null || dayOfMonth == null || month < 1 || month > 12) return day;
  return '$dayOfMonth ${_months[month - 1]}';
}
