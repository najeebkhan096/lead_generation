// Human labels for lead data shown on cards.

/// The backend tags a category with its country ("Car Dealer USA") so the
/// same category in two countries stays apart; that tag is noise on screen.
String cleanCategory(String? category) {
  final c = (category ?? '').trim();
  if (c.isEmpty) return 'Other';
  return c.replaceFirst(RegExp(r'\s+USA$', caseSensitive: false), '');
}

/// "www.example.com" from a full URL, for compact display. Null when [url] is
/// empty or not a usable address.
String? hostOf(String? url) {
  final raw = (url ?? '').trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  final host = uri?.host ?? '';
  return host.isEmpty ? null : host.replaceFirst(RegExp(r'^www\.'), '');
}

/// "4.2 · 118 reviews", "4.2", or null when there is no rating.
String? ratingLabel(double? rating, int? reviews) {
  if (rating == null || rating <= 0) return null;
  final r = rating.toStringAsFixed(1);
  if (reviews == null || reviews <= 0) return r;
  return '$r · $reviews review${reviews == 1 ? '' : 's'}';
}
