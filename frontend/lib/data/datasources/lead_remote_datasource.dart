import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/search_progress.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/entities/whatsapp_web_status.dart';

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
    String country = 'US',
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
            'maxResultsPerState': 150,
            'country': country,
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
            ? 'Nationwide search started — scanning regions…'
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
        currentState: (progressMap?['state'] as String?) ?? '',
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

  /// Records a manually-checked WhatsApp result for one lead (e.g. checked
  /// by hand on a phone rather than through the automated validation job).
  /// [leadId] must be the lead's Firestore [Lead.dbId].
  Future<void> markLeadWhatsAppStatus(String leadId, bool hasWhatsApp) async {
    final response = await _client.patch(
      _uri(ApiConstants.leadWhatsAppStatus(leadId)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'hasWhatsApp': hasWhatsApp}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to update WhatsApp status');
    }
  }

  /// Deletes a single saved lead from Firestore. [leadId] must be the
  /// lead's Firestore [Lead.dbId].
  Future<void> deleteLead(String leadId) async {
    final response = await _client.delete(_uri(ApiConstants.leadDelete(leadId)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete lead');
    }
  }

  /// Deletes every saved lead in an exact category (the country-tagged
  /// string, e.g. "cleaning services UK" — see [Lead.category]). Returns
  /// the number of leads deleted.
  Future<int> deleteLeadsByCategory(String category) async {
    final response = await _client.delete(
      _uri(ApiConstants.savedLeads).replace(queryParameters: {'category': category}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to delete leads');
    }
    return (body['deleted'] as num?)?.toInt() ?? 0;
  }

  /// Deletes every lead and search record from Firestore. Requires the
  /// backend's exact confirm phrase — see [ApiConstants.clearDb].
  Future<String> clearAllData() async {
    final response = await _client
        .post(
          _uri(ApiConstants.clearDb),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'confirm': 'DELETE ALL DATA'}),
        )
        .timeout(const Duration(seconds: 60));

    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to clear database');
    }
    return (body['message'] as String?) ?? 'All data cleared.';
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

  /// [countries], when given more than one code, runs every category in
  /// [categories] against every country concurrently (one worker per
  /// (category, country) pair) — "search this category in all countries."
  /// Omit it (or pass a single-element list) for the ordinary single-country
  /// multi-category search.
  Future<void> startMultiSearch({
    required List<String> categories,
    List<String>? countries,
    int concurrency = 4,
    String dateRange = '30',
    int maxResultsPerState = 150,
    int targetLeadCount = 100,
    bool analyze = false,
    String country = 'US',
  }) async {
    final response = await _client
        .post(
          _uri(ApiConstants.multiSearch),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'categories': categories,
            if (countries != null) 'countries': countries,
            'concurrency': concurrency,
            'dateRange': dateRange,
            'maxResultsPerState': maxResultsPerState,
            'targetLeadCount': targetLeadCount,
            'analyze': analyze,
            'country': country,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start multi-category search');
    }
  }

  Future<MultiSearchSnapshot> getMultiSearchStatus() async {
    final response = await _client.get(_uri(ApiConstants.multiSearchStatus));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load multi-search status');
    }
    return MultiSearchSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _postControl(String path, {String? category, String? country}) async {
    final response = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (category != null) 'category': category,
        if (country != null) 'country': country,
      }),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
  }

  Future<void> cancelMultiSearchJob() => _postControl(ApiConstants.multiSearchCancel);

  /// [country] disambiguates which country's run of [category] to target —
  /// required when the job covers more than one country for the same
  /// category (see [startMultiSearch]'s `countries`), optional otherwise.
  Future<void> cancelMultiSearchCategory(String category, {String? country}) =>
      _postControl(ApiConstants.multiSearchCancelCategory, category: category, country: country);
  Future<void> pauseMultiSearchJob() => _postControl(ApiConstants.multiSearchPause);
  Future<void> resumeMultiSearchJob() => _postControl(ApiConstants.multiSearchResume);
  Future<void> pauseMultiSearchCategory(String category, {String? country}) =>
      _postControl(ApiConstants.multiSearchPauseCategory, category: category, country: country);
  Future<void> resumeMultiSearchCategory(String category, {String? country}) =>
      _postControl(ApiConstants.multiSearchResumeCategory, category: category, country: country);

  Future<WhatsAppWebStatus> getWhatsAppWebStatus() async {
    final response = await _client.get(_uri(ApiConstants.whatsAppWebStatus));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load WhatsApp Web status');
    }
    return WhatsAppWebStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> connectWhatsAppWeb() async {
    final response = await _client.post(_uri(ApiConstants.whatsAppWebConnect));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start WhatsApp Web connection');
    }
  }

  Future<void> disconnectWhatsAppWeb() async {
    final response = await _client.post(_uri(ApiConstants.whatsAppWebDisconnect));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to disconnect WhatsApp Web');
    }
  }

  /// [leads] is a list of `{id, phone, business}` maps — `id` must be the
  /// lead's Firestore `dbId`, not its display id.
  Future<void> startWhatsAppValidation(List<Map<String, String>> leads) async {
    final response = await _client.post(
      _uri(ApiConstants.whatsAppWebValidate),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'leads': leads}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start WhatsApp validation');
    }
  }

  Future<void> startWhatsAppAutoValidation() async {
    final response = await _client.post(_uri(ApiConstants.whatsAppWebValidateAuto));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start auto WhatsApp validation');
    }
  }

  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() async {
    final response = await _client.get(_uri(ApiConstants.whatsAppWebValidateStatus));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load validation status');
    }
    return WhatsAppValidationSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> cancelWhatsAppValidation() async {
    final response = await _client.post(_uri(ApiConstants.whatsAppWebValidateCancel));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to cancel validation');
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
