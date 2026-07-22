// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void downloadTextFile(String filename, String content, String mimeType) {
  final bytes = html.Blob([content], mimeType);
  final url = html.Url.createObjectUrlFromBlob(bytes);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
