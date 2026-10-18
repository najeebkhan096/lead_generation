// Human labels for lead data shown on cards.

/// The backend tags a category with its country ("Car Dealer USA") so the
/// same category in two countries stays apart; that tag is noise on screen.
String cleanCategory(String? category) {
  final c = (category ?? '').trim();
  if (c.isEmpty) return 'Other';
  return c.replaceFirst(RegExp(r'\s+USA$', caseSensitive: false), '');
}

/// "4.2 · 118 reviews", "4.2", or null when there is no rating.
String? ratingLabel(double? rating, int? reviews) {
  if (rating == null || rating <= 0) return null;
  final r = rating.toStringAsFixed(1);
  if (reviews == null || reviews <= 0) return r;
  return '$r · $reviews review${reviews == 1 ? '' : 's'}';
}
