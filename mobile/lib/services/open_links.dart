import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
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

Future<bool> openEmail(String? email) async {
  final trimmed = (email ?? '').trim();
  if (trimmed.isEmpty) return false;
  return openExternalUrl('mailto:$trimmed');
}

Future<bool> openWebsite(String? website) async {
  final trimmed = (website ?? '').trim();
  if (trimmed.isEmpty) return false;
  final hasScheme = trimmed.startsWith('http://') || trimmed.startsWith('https://');
  return openExternalUrl(hasScheme ? trimmed : 'https://$trimmed');
}
