import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart' as impl;

/// Triggers a browser file download on web; no-op on other platforms.
void downloadTextFile(String filename, String content, String mimeType) {
  impl.downloadTextFile(filename, content, mimeType);
}
