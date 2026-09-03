import 'dart:convert';

/// Deterministically hashes [input] to a 32-bit integer (FNV-1a). Used
/// instead of Dart's built-in [String.hashCode], which is only guaranteed
/// consistent within a single run — not across app restarts, platforms, or
/// SDK versions — which would defeat the whole point of [seededShuffle]
/// needing a *stable* per-seed order.
int _fnv1aHash(String input) {
  const prime = 0x01000193; // 16777619
  var hash = 0x811c9dc5; // FNV offset basis
  for (final byte in utf8.encode(input)) {
    hash = ((hash ^ byte) * prime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Reorders [items] using a pseudo-random order derived from [seed] plus
/// each item's own key (from [keyOf]) — not from the items' original order
/// or count, so appending/removing items elsewhere in the list never
/// disturbs everyone else's relative order.
///
/// The same [seed] always produces the same order for the same items (no
/// reshuffling on every rebuild/stream update), but different seeds produce
/// different orders. Built for showing the same shared lead pool to
/// multiple salesmen (seeded by their uid) without everyone working through
/// it in identical newest-first order and piling onto the same businesses.
List<T> seededShuffle<T>(List<T> items, String Function(T item) keyOf, String seed) {
  final ranked = items.map((item) => (item, _fnv1aHash('$seed::${keyOf(item)}'))).toList()
    ..sort((a, b) => a.$2.compareTo(b.$2));
  return ranked.map((e) => e.$1).toList(growable: false);
}
