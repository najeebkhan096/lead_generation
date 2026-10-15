const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a date as e.g. "Jul 25, 2026". Returns `null` when [date] is null.
String? formatDate(DateTime? date) {
  if (date == null) return null;
  final local = date.toLocal();
  return '${_monthNames[local.month - 1]} ${local.day}, ${local.year}';
}

/// Formats a time as e.g. "3:45 PM" (local). Returns `null` when [date] is null.
String? formatTime(DateTime? date) {
  if (date == null) return null;
  final local = date.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

/// Formats a moment as e.g. "Oct 12, 2026 · 3:45 PM". `null` when [date] is null.
String? formatDateTime(DateTime? date) {
  if (date == null) return null;
  return '${formatDate(date)} · ${formatTime(date)}';
}
