/// Formats a duration as e.g. "1h 4m 12s", "4m 12s", or "12s".
String formatDuration(Duration duration) {
  final ms = duration.inMilliseconds;
  if (ms <= 0) return '0s';
  final totalSeconds = (ms / 1000).round();
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
