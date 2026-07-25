import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/search_progress.dart';

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
    required String category,
    required String dateRange,
    String location = 'All US states',
    bool nationwide = true,
    int targetLeadCount = 100,
    bool analyze = false,
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
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
            'nationwide': nationwide,
            'targetLeadCount': targetLeadCount,
            'maxResultsPerState': 16,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (start.statusCode == 409) {
      onProgress?.call(
        const SearchProgress(message: 'Search already running…'),
        const [],
      );
    } else if (start.statusCode >= 400) {
      final body = _tryDecode(start.body);
      throw Exception(body['error'] ?? 'Search failed (${start.statusCode})');
    }

    onProgress?.call(
      SearchProgress(
        message: nationwide
            ? 'Nationwide search started — scanning U.S. states…'
            : 'Search started…',
        targetCount: targetLeadCount,
      ),
      const [],
    );

    final deadline = DateTime.now().add(
      Duration(hours: nationwide ? 3 : 1),
    );

    var lastLeadFetch = -1;
    var liveLeads = <Lead>[];

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
      final progressMap = statusBody['progress'] as Map<String, dynamic>?;
      final lastSearch = statusBody['lastSearch'] as Map<String, dynamic>?;
      final leadCount = (statusBody['leadCount'] as num?)?.toInt() ??
          (progressMap?['found'] as num?)?.toInt() ??
          0;
      final target = (lastSearch?['targetLeadCount'] as num?)?.toInt() ?? targetLeadCount;

      final progress = SearchProgress(
        message: (progressMap?['message'] as String?) ?? '',
        leadCount: leadCount,
        targetCount: target,
        statesDone: (progressMap?['statesDone'] as num?)?.toInt() ?? 0,
        statesTotal: (progressMap?['statesTotal'] as num?)?.toInt() ?? 0,
        businessesScraped: (progressMap?['processed'] as num?)?.toInt() ?? 0,
      );

      if (leadCount > 0 && leadCount != lastLeadFetch) {
        lastLeadFetch = leadCount;
        try {
          liveLeads = await getResults();
        } catch (_) {
          // keep previous list
        }
      }

      onProgress?.call(progress, liveLeads);

      if (status == 'done') {
        return liveLeads.isNotEmpty ? liveLeads : getResults();
      }
      if (status == 'error') {
        throw Exception(
          statusBody['error'] as String? ?? 'Search failed',
        );
      }
    }

    throw Exception(
      'Search timed out. Check results or restart the server.',
    );
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

  Future<String> saveToDatabase() async {
    final response = await _client
        .post(
          _uri(ApiConstants.saveToDb),
          headers: {'Content-Type': 'application/json'},
          body: '{}',
        )
        .timeout(const Duration(seconds: 60));

    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Save to Firebase failed');
    }
    return (body['message'] as String?) ??
        'Saved ${(body['total'] as num?)?.toInt() ?? 0} leads to Firebase.';
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
