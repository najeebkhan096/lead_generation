import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/search_progress.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/entities/whatsapp_web_status.dart';

class LeadRemoteDataSource {
  LeadRemoteDataSource({http.Client? client})
    : _client = client ?? http.Client();

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
    final res = await _client
        .get(_uri(ApiConstants.status))
        .timeout(const Duration(seconds: 30));
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
    final deadline = DateTime.now().add(Duration(hours: nationwide ? 3 : 1));

    var lastLeadFetch = -1;
    var liveLeads = <Lead>[];

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));

      final statusRes = await _client
          .get(_uri(ApiConstants.status))
          .timeout(const Duration(seconds: 30));

      if (statusRes.statusCode >= 400) {
        throw Exception(
          'Failed to poll search status (${statusRes.statusCode})',
        );
      }

      final statusBody = jsonDecode(statusRes.body) as Map<String, dynamic>;
      final status = statusBody['status'] as String? ?? '';
      final progressMap = statusBody['progress'] as Map<String, dynamic>?;
      final lastSearch = statusBody['lastSearch'] as Map<String, dynamic>?;
      final leadCount =
          (statusBody['leadCount'] as num?)?.toInt() ??
          (progressMap?['found'] as num?)?.toInt() ??
          0;
      final target =
          (lastSearch?['targetLeadCount'] as num?)?.toInt() ?? targetLeadCount;

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
        throw Exception(statusBody['error'] as String? ?? 'Search failed');
      }
    }

    throw Exception('Search timed out. Check results or restart the server.');
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

  /// The current single search's leads as an .xlsx workbook (one sheet).
  Future<Uint8List> exportExcel() async {
    final response = await _client.get(_uri(ApiConstants.exportXlsx));
    if (response.statusCode >= 400) {
      final body = _tryDecode(String.fromCharCodes(response.bodyBytes));
      throw Exception(body['error'] ?? 'Excel export failed');
    }
    return response.bodyBytes;
  }

  /// The most recent multi-category (and/or multi-country) scan as one
  /// .xlsx workbook with one sheet per category.
  Future<Uint8List> exportMultiExcel() async {
    final response = await _client.get(_uri(ApiConstants.exportXlsxMulti));
    if (response.statusCode >= 400) {
      final body = _tryDecode(String.fromCharCodes(response.bodyBytes));
      throw Exception(body['error'] ?? 'Excel export failed');
    }
    return response.bodyBytes;
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
      _uri(ApiConstants.savedLeads).replace(queryParameters: {'limit': '5000'}),
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
    final response = await _client.delete(
      _uri(ApiConstants.leadDelete(leadId)),
    );
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
      _uri(
        ApiConstants.savedLeads,
      ).replace(queryParameters: {'category': category}),
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
    bool exportOnly = false,
    String country = 'US',
  }) async {
    final response = await _client
        .post(
          _uri(ApiConstants.multiSearch),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'categories': categories,
            'countries': ?countries,
            'concurrency': concurrency,
            'dateRange': dateRange,
            'maxResultsPerState': maxResultsPerState,
            'targetLeadCount': targetLeadCount,
            'analyze': analyze,
            'exportOnly': exportOnly,
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
    return MultiSearchSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _postControl(
    String path, {
    String? category,
    String? country,
  }) async {
    final response = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'category': ?category, 'country': ?country}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
  }

  Future<void> cancelMultiSearchJob() =>
      _postControl(ApiConstants.multiSearchCancel);

  /// [country] disambiguates which country's run of [category] to target —
  /// required when the job covers more than one country for the same
  /// category (see [startMultiSearch]'s `countries`), optional otherwise.
  Future<void> cancelMultiSearchCategory(String category, {String? country}) =>
      _postControl(
        ApiConstants.multiSearchCancelCategory,
        category: category,
        country: country,
      );
  Future<void> pauseMultiSearchJob() =>
      _postControl(ApiConstants.multiSearchPause);
  Future<void> resumeMultiSearchJob() =>
      _postControl(ApiConstants.multiSearchResume);
  Future<void> pauseMultiSearchCategory(String category, {String? country}) =>
      _postControl(
        ApiConstants.multiSearchPauseCategory,
        category: category,
        country: country,
      );
  Future<void> resumeMultiSearchCategory(String category, {String? country}) =>
      _postControl(
        ApiConstants.multiSearchResumeCategory,
        category: category,
        country: country,
      );

  Future<WhatsAppWebStatus> getWhatsAppWebStatus() async {
    final response = await _client.get(_uri(ApiConstants.whatsAppWebStatus));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load WhatsApp Web status');
    }
    return WhatsAppWebStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> connectWhatsAppWeb() async {
    final response = await _client.post(_uri(ApiConstants.whatsAppWebConnect));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(
        body['error'] ?? 'Failed to start WhatsApp Web connection',
      );
    }
  }

  Future<void> disconnectWhatsAppWeb() async {
    final response = await _client.post(
      _uri(ApiConstants.whatsAppWebDisconnect),
    );
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

  /// Same guarded validation job as [startWhatsAppValidation], but for
  /// leads that were never saved to Firestore (e.g. extracted from an
  /// Excel archive) — `id` here is just a correlation key for reading
  /// back [WhatsAppValidationSnapshot.results], not a real document id.
  Future<void> validateExternalLeads(List<Map<String, String>> leads) async {
    final response = await _client.post(
      _uri(ApiConstants.whatsAppWebValidateList),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'leads': leads}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start WhatsApp validation');
    }
  }

  Future<void> startWhatsAppAutoValidation() async {
    final response = await _client.post(
      _uri(ApiConstants.whatsAppWebValidateAuto),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(
        body['error'] ?? 'Failed to start auto WhatsApp validation',
      );
    }
  }

  Future<WhatsAppValidationSnapshot> getWhatsAppValidationStatus() async {
    final response = await _client.get(
      _uri(ApiConstants.whatsAppWebValidateStatus),
    );
    if (response.statusCode >= 400) {
      throw Exception('Failed to load validation status');
    }
    return WhatsAppValidationSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> cancelWhatsAppValidation() async {
    final response = await _client.post(
      _uri(ApiConstants.whatsAppWebValidateCancel),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to cancel validation');
    }
  }

  /// Adds a business to the watchlist (idempotent per URL server-side).
  Future<WatchlistEntry> addWatchlistEntry({
    required String url,
    String? name,
    String country = 'US',
    String? assignedTo,
    String? assignedToName,
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.watchlist),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'url': url,
        'name': name,
        'country': country,
        'assignedTo': ?assignedTo,
        'assignedToName': ?assignedToName,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to add business');
    }
    return WatchlistEntry.fromJson(body['entry'] as Map<String, dynamic>);
  }

  /// Reassigns (or clears, passing both null) which salesman a watchlist
  /// entry is assigned to.
  Future<WatchlistEntry> assignWatchlistEntry(
    String id, {
    String? assignedTo,
    String? assignedToName,
  }) async {
    final response = await _client.patch(
      _uri(ApiConstants.watchlistAssign(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'assignedTo': ?assignedTo,
        'assignedToName': ?assignedToName,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to assign business');
    }
    return WatchlistEntry.fromJson(body['entry'] as Map<String, dynamic>);
  }

  /// Salesmen (mobile app users) available to assign watchlist businesses to.
  Future<List<SalesUser>> listSalesmen() async {
    final response = await _client.get(
      _uri(ApiConstants.users).replace(queryParameters: {'role': 'salesman'}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load salesmen');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final usersJson = (body['users'] as List<dynamic>? ?? []);
    return usersJson.map((e) => SalesUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<WatchlistEntry>> listWatchlist() async {
    final response = await _client.get(_uri(ApiConstants.watchlist));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load watchlist');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final entriesJson = (body['entries'] as List<dynamic>? ?? []);
    return entriesJson
        .map((e) => WatchlistEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteWatchlistEntry(String id) async {
    final response = await _client.delete(_uri(ApiConstants.watchlistDelete(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to remove business');
    }
  }

  /// Scans every watchlisted business now and returns which ones have new
  /// reviews since the last scan. Can take a while (real page loads, one
  /// business at a time), so the request timeout is generous. [dateRange]
  /// (days) bounds how far back a review can be and still count as "new".
  Future<List<WatchlistScanResult>> scanWatchlist({String dateRange = '30'}) async {
    final response = await _client
        .post(
          _uri(ApiConstants.watchlistScan),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'dateRange': dateRange}),
        )
        .timeout(const Duration(minutes: 20));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Watchlist scan failed');
    }
    final resultsJson = (body['results'] as List<dynamic>? ?? []);
    return resultsJson
        .map((e) => WatchlistScanResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ExcelArchive>> listExcelArchives() async {
    final response = await _client.get(_uri(ApiConstants.excelArchives));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load Excel archives');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final archivesJson = (body['archives'] as List<dynamic>? ?? []);
    return archivesJson.map((e) => ExcelArchive.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ExcelArchiveSheet>> getExcelArchiveData(String id) async {
    final response = await _client.get(_uri(ApiConstants.excelArchiveData(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load archive data');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sheetsJson = (body['sheets'] as List<dynamic>? ?? []);
    return sheetsJson.map((e) => ExcelArchiveSheet.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Reads an archive's rows back as [Lead]s (never saved to Firestore —
  /// `dbId` is always null) so they can be shown with the same `LeadCard`
  /// widget used everywhere else in the app.
  Future<List<Lead>> getExcelArchiveLeads(String id) async {
    final response = await _client.get(_uri(ApiConstants.excelArchiveLeads(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to extract leads from archive');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final leadsJson = (body['leads'] as List<dynamic>? ?? []);
    return leadsJson.map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Uploads a set of WhatsApp-validated leads (grouped by category, one
  /// sheet each) as an .xlsx to Firebase Storage under the
  /// `whatsappValidatedScans` collection — a separate archive from the
  /// source Excel scan it was validated from.
  Future<ExcelArchive> uploadValidatedArchive({
    required List<Map<String, dynamic>> sheets,
    String? sourceArchiveId,
    String? sourceFileName,
    List<String>? countries,
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.whatsappValidatedScans),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sheets': sheets,
        'sourceArchiveId': ?sourceArchiveId,
        'sourceFileName': ?sourceFileName,
        'countries': ?countries,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to upload validated businesses');
    }
    return ExcelArchive.fromJson(body['archive'] as Map<String, dynamic>);
  }

  Future<List<ExcelArchive>> listValidatedArchives() async {
    final response = await _client.get(_uri(ApiConstants.whatsappValidatedScans));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load validated archives');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final archivesJson = (body['archives'] as List<dynamic>? ?? []);
    return archivesJson.map((e) => ExcelArchive.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ExcelArchiveSheet>> getValidatedArchiveData(String id) async {
    final response = await _client.get(_uri(ApiConstants.whatsappValidatedData(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load archive data');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sheetsJson = (body['sheets'] as List<dynamic>? ?? []);
    return sheetsJson.map((e) => ExcelArchiveSheet.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Lead>> getValidatedArchiveLeads(String id) async {
    final response = await _client.get(_uri(ApiConstants.whatsappValidatedLeads(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to extract leads from archive');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final leadsJson = (body['leads'] as List<dynamic>? ?? []);
    return leadsJson.map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteValidatedArchive(String id) async {
    final response = await _client.delete(_uri(ApiConstants.whatsappValidatedDelete(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete archive');
    }
  }

  Future<void> deleteExcelArchive(String id) async {
    final response = await _client.delete(_uri(ApiConstants.excelArchiveDelete(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete archive');
    }
  }

  Future<Sale> createSale({
    required String businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    double price = 0,
    double salesmanPrice = 0,
    SaleStatus status = SaleStatus.orderPlaced,
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.sales),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'businessName': businessName,
        'reviewLink': ?reviewLink,
        'salesmanId': ?salesmanId,
        'salesmanName': ?salesmanName,
        'price': price,
        'salesmanPrice': salesmanPrice,
        'status': status.json,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to create sale');
    }
    return Sale.fromJson(body['sale'] as Map<String, dynamic>);
  }

  Future<List<Sale>> listSales({String? salesmanId}) async {
    final response = await _client.get(
      _uri(ApiConstants.sales).replace(queryParameters: salesmanId == null ? null : {'salesmanId': salesmanId}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load sales');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final salesJson = (body['sales'] as List<dynamic>? ?? []);
    return salesJson.map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Sale> updateSale(
    String id, {
    String? businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    double? price,
    double? salesmanPrice,
    SaleStatus? status,
  }) async {
    final response = await _client.patch(
      _uri(ApiConstants.saleUpdate(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'businessName': ?businessName,
        'reviewLink': ?reviewLink,
        'salesmanId': ?salesmanId,
        'salesmanName': ?salesmanName,
        'price': ?price,
        'salesmanPrice': ?salesmanPrice,
        'status': ?status?.json,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to update sale');
    }
    return Sale.fromJson(body['sale'] as Map<String, dynamic>);
  }

  Future<void> deleteSale(String id) async {
    final response = await _client.delete(_uri(ApiConstants.saleDelete(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete sale');
    }
  }

  Future<SalesStats> getSalesStats({String? salesmanId}) async {
    final response = await _client.get(
      _uri(ApiConstants.salesStats).replace(queryParameters: salesmanId == null ? null : {'salesmanId': salesmanId}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load sales stats');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return SalesStats.fromJson(body['stats'] as Map<String, dynamic>);
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
