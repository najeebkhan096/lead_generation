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
