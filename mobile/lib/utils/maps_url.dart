/// Google Maps link handling for client businesses. Mirrors
/// backend/src/lib/mapsUrl.js so the form rejects what the server would.
final _googleHost = RegExp(r'(^|\.)google\.[a-z.]{2,}$', caseSensitive: false);
const _shortHosts = {'goo.gl', 'maps.app.goo.gl', 'g.page', 'g.co', 'share.google'};

/// Returns a clean https link for a Google Maps listing, or null when [raw]
/// is not a Google link. Adds a missing scheme; never rewrites the rest.
String? normalizeMapsUrl(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
  final hasScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(text);
  final withScheme = hasScheme ? text : 'https://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || !uri.hasAuthority) return null;
  final host = uri.host.toLowerCase();
  if (!host.contains('.')) return null;
  if (!_googleHost.hasMatch(host) && !_shortHosts.contains(host)) return null;
  if ((uri.path.isEmpty || uri.path == '/') && !uri.hasQuery && !uri.hasFragment) return null;
  return withScheme.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
}

/// Lowercased, whitespace-collapsed name used to recognise the same business.
String clientNameKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
