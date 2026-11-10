// Defensive JSON readers shared by the Jobs entities. The API stores unknown
// values as `null`, and that must stay `null` here — never a made-up default.

DateTime? jobDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

int? jobInt(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

double? jobDouble(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

String? jobString(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

List<String> jobStrings(Object? v) =>
    v is List ? [for (final e in v) if (e is String && e.trim().isNotEmpty) e] : const [];

Map<String, dynamic> jobMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> jobMaps(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

/// "12430" -> "12,430".
String thousands(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "full_time" -> "Full time".
String humanize(String? snake) {
  if (snake == null || snake.isEmpty) return '';
  final words = snake.replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}
