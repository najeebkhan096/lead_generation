import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/lead.dart';

class LeadRemoteDataSource {
  LeadRemoteDataSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${ApiConstants.baseUrl}$path');

  Future<List<Lead>> searchLeads({
    required String location,
    required String category,
    required String dateRange,
    bool analyze = false,
  }) async {
    final response = await _client
        .post(
          _uri(ApiConstants.search),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'location': location,
            'category': category,
            'dateRange': dateRange,
            'analyze': analyze,
            'maxResults': 12,
          }),
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Search failed (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final leadsJson = (body['leads'] as List<dynamic>? ?? []);
    return leadsJson
        .map((e) => Lead.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Lead>> getResults() async {
    final response = await _client.get(_uri(ApiConstants.results));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load results');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final leadsJson = (body['leads'] as List<dynamic>? ?? []);
    return leadsJson
        .map((e) => Lead.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> exportCsv() async {
    final response = await _client.get(_uri(ApiConstants.exportCsv));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'CSV export failed');
    }
    return response.body;
  }

  Future<String> exportJson() async {
    final response = await _client.get(_uri(ApiConstants.exportJson));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'JSON export failed');
    }
    return response.body;
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
