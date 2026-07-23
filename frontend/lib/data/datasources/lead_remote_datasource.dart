import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/lead.dart';

class LeadRemoteDataSource {
  LeadRemoteDataSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) {
    final base = ApiConstants.baseUrl.trim();
    if (base.isEmpty) {
      final p = path.startsWith('/') ? path : '/$path';
      return Uri.parse(p);
    }
    return Uri.parse('$base$path');
  }

  /// Starts search (202) then polls status until done — avoids Render 502 timeouts.
  Future<List<Lead>> searchLeads({
    required String location,
    required String category,
    required String dateRange,
    bool analyze = false,
    void Function(String message)? onProgress,
  }) async {
    final start = await _client
        .post(
          _uri(ApiConstants.search),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'location': location,
            'category': category,
            'dateRange': dateRange,
            'analyze': analyze,
            'maxResults': 8,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (start.statusCode == 409) {
      onProgress?.call('Search already running…');
    } else if (start.statusCode >= 400) {
      final body = _tryDecode(start.body);
      throw Exception(body['error'] ?? 'Search failed (${start.statusCode})');
    }

    onProgress?.call('Search started…');

    final deadline = DateTime.now().add(const Duration(minutes: 12));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));

      final statusRes = await _client
          .get(_uri(ApiConstants.status))
          .timeout(const Duration(seconds: 30));

      if (statusRes.statusCode >= 400) {
        throw Exception('Failed to poll search status (${statusRes.statusCode})');
      }

      final statusBody = jsonDecode(statusRes.body) as Map<String, dynamic>;
      final status = statusBody['status'] as String? ?? '';
      final progress = statusBody['progress'] as Map<String, dynamic>?;
      final message = progress?['message'] as String?;
      if (message != null && message.isNotEmpty) {
        onProgress?.call(message);
      }

      if (status == 'done') {
        return getResults();
      }
      if (status == 'error') {
        throw Exception(
          statusBody['error'] as String? ?? 'Search failed',
        );
      }
    }

    throw Exception('Search timed out. Try again with a smaller date range.');
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
