import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static String get baseUrl {
    const custom = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (custom.isNotEmpty) return custom;
    if (kIsWeb) return 'http://localhost:3001';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:3001';
    } catch (_) {}
    return 'http://127.0.0.1:3001';
  }

  Future<void> deleteValidatedArchive(String id) async {
    final response = await http
        .delete(Uri.parse('$baseUrl/api/whatsapp-validated-scans/$id'))
        .timeout(const Duration(seconds: 6));
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
