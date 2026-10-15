import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// [waUrl] (a wa.me chat link) with [text] prefilled in the message box.
/// Percent-encoded, spaces as `%20`; unchanged when there is no text or no
/// link.
String? whatsAppUrlWithText(String? waUrl, String? text) {
  final url = (waUrl ?? '').trim();
  if (url.isEmpty || text == null || text.isEmpty) return waUrl;
  final base = url.contains('?') ? url.substring(0, url.indexOf('?')) : url;
  return '$base?text=${Uri.encodeComponent(text)}';
}

Future<bool> openWhatsApp(String? waUrl) async {
  if (waUrl == null || waUrl.trim().isEmpty) return false;
  return openExternalUrl(waUrl);
}

Future<bool> openGoogleMaps(String? mapsUrl) async {
  if (mapsUrl == null || mapsUrl.trim().isEmpty) return false;
  return openExternalUrl(mapsUrl);
}

Future<bool> openPhone(String? phone) async {
  final digits = (phone ?? '').trim();
  if (digits.isEmpty) return false;
  return openExternalUrl('tel:$digits');
}

/// A `mailto:` link to [to], with an optional [subject] and [body].
///
/// Components are percent-encoded (spaces as `%20` — the `+` form is shown
/// literally by mail apps) and line breaks are CRLF, as RFC 6068 asks.
String mailtoUrl(String to, {String? subject, String? body}) {
  final query = <String>[
    if (subject != null && subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
    if (body != null && body.isNotEmpty)
      'body=${Uri.encodeComponent(body.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'))}',
  ];
  return query.isEmpty ? 'mailto:$to' : 'mailto:$to?${query.join('&')}';
}

/// Opens the phone's mail app with a new message to [email]. The sender is
/// whichever account the mail app is set to send from — a `mailto:` link
/// cannot choose it.
Future<bool> openEmail(String? email, {String? subject, String? body}) async {
  final trimmed = (email ?? '').trim();
  if (trimmed.isEmpty) return false;
  return openExternalUrl(mailtoUrl(trimmed, subject: subject, body: body));
}

Future<bool> openWebsite(String? website) async {
  final trimmed = (website ?? '').trim();
  if (trimmed.isEmpty) return false;
  final hasScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://');
  return openExternalUrl(hasScheme ? trimmed : 'https://$trimmed');
}
