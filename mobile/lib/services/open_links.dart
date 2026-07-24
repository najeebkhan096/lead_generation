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
