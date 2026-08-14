import 'dart:convert';
import 'package:http/http.dart' as http;

/// Talks to the backend Express server — which only runs on the desktop
/// Launcher's machine, unreachable from a phone off that network. Kept
/// deliberately minimal: everything that can be read straight from
/// Firebase (archive listing/browsing — see ArchiveRepository) has been
/// moved off this class so those features work with no backend at all.
/// Only mutations that must go through the Admin SDK (deleting a
/// WhatsApp-verified archive's Storage file) still live here — the Excel
/// Archive page deliberately has no delete option (see excel_archive_page.dart).
class ApiService {
  // Use 10.0.2.2 for Android Emulator to reach the host machine's localhost.
  // Only matters for the delete call below — everything else in this app
  // talks to Firebase directly and doesn't need this at all.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  Future<void> deleteValidatedArchive(String id) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/whatsapp-validated-scans/$id'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete archive');
    }
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
