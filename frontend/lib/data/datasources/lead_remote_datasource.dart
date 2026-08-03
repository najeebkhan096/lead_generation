import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/search_progress.dart';
import '../../domain/entities/whatsapp_check_result.dart';

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
    String? category,
    List<String>? categories,
    required String dateRange,
    String location = 'All US states',
    bool nationwide = true,
    int targetLeadCount = 100,
    bool analyze = false,
    bool autoSave = true,
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) async {
    final start = await _client
        .post(
          _uri(ApiConstants.search),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'location': location,
            'category': category,
            'categories': categories,
            'dateRange': dateRange,
            'analyze': analyze,
            'autoSave': autoSave,
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

    return _pollUntilDone(
      nationwide: nationwide,
      targetLeadCount: targetLeadCount,
      onProgress: onProgress,
    );
  }

  /// Checks the server's current search state without starting anything.
  ///
  /// Search progress lives only in the backend's in-memory store, so a page
  /// reload (or the dev server restarting) otherwise loses all visibility
  /// into a search that's still running or already finished. Returns `null`
  /// when there's nothing to resume (server is idle).
  Future<Map<String, dynamic>?> getSearchSnapshot() async {
    final res = await _client.get(_uri(ApiConstants.status)).timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if ((body['status'] as String? ?? 'idle') == 'idle') return null;
    return body;
  }

  /// Resumes watching a search already running server-side (from
  /// [getSearchSnapshot]), or immediately returns its results if it already
  /// finished.
  Future<List<Lead>> resumeSearch(
    Map<String, dynamic> snapshot, {
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) async {
    final status = snapshot['status'] as String? ?? '';
    if (status == 'done') return getResults();
    if (status == 'error') {
      throw Exception(snapshot['error'] as String? ?? 'Search failed');
    }

    final lastSearch = snapshot['lastSearch'] as Map<String, dynamic>?;
    return _pollUntilDone(
      nationwide: lastSearch?['nationwide'] == true,
      targetLeadCount: (lastSearch?['targetLeadCount'] as num?)?.toInt() ?? 100,
      onProgress: onProgress,
    );
  }

  Future<List<Lead>> _pollUntilDone({
    required bool nationwide,
    required int targetLeadCount,
    void Function(SearchProgress progress, List<Lead> liveLeads)? onProgress,
  }) async {
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
        currentCategory: lastSearch?['category'] as String? ?? '',
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

  /// Fetches every business persisted to Firestore via the backend proxy.
  Future<List<Lead>> getSavedLeads() async {
    final response = await _client.get(
      _uri(ApiConstants.savedLeads).replace(queryParameters: {'limit': '500'}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load saved businesses');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final leadsJson = (body['leads'] as List<dynamic>? ?? []);
    return leadsJson
        .map((e) => Lead.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Checks whether [phone] is reachable on WhatsApp.
  Future<WhatsAppCheckResult> checkWhatsApp(String phone) async {
    final response = await _client
        .post(
          _uri(ApiConstants.checkWhatsApp),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        )
        .timeout(const Duration(seconds: 40));

    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'WhatsApp check failed');
    }
    return WhatsAppCheckResult.fromJson(body);
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
