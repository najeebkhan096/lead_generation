import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/excel_archive.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator to reach the host machine's localhost
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  Future<Map<String, dynamic>> startWhatsAppAutoValidation() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/whatsapp-web/validate-auto'),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getWhatsAppValidationStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/whatsapp-web/validate/status'),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getWhatsAppStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/whatsapp-web/status'),
    );
    return jsonDecode(response.body);
  }

  Future<List<ExcelArchive>> listExcelArchives() async {
    final response = await http.get(Uri.parse('$baseUrl/api/excel-scans'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load Excel archives');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final archivesJson = (body['archives'] as List<dynamic>? ?? []);
    return archivesJson.map((e) => ExcelArchive.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ExcelArchiveSheet>> getExcelArchiveData(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/api/excel-scans/$id/data'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load archive data');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sheetsJson = (body['sheets'] as List<dynamic>? ?? []);
    return sheetsJson.map((e) => ExcelArchiveSheet.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteExcelArchive(String id) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/excel-scans/$id'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete archive');
    }
  }

  Future<List<ExcelArchive>> listValidatedArchives() async {
    final response = await http.get(Uri.parse('$baseUrl/api/whatsapp-validated-scans'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load verified archives');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final archivesJson = (body['archives'] as List<dynamic>? ?? []);
    return archivesJson.map((e) => ExcelArchive.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ExcelArchiveSheet>> getValidatedArchiveData(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/api/whatsapp-validated-scans/$id/data'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load archive data');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sheetsJson = (body['sheets'] as List<dynamic>? ?? []);
    return sheetsJson.map((e) => ExcelArchiveSheet.fromJson(e as Map<String, dynamic>)).toList();
  }

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
