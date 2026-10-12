import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/email_validation_snapshot.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_page.dart';
import '../../domain/entities/multi_search_snapshot.dart';
import '../../domain/entities/state_city_scan_snapshot.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/sale.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../../domain/entities/whatsapp_check_result.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/entities/outreach.dart';

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

  /// Deletes a single saved website lead from Firestore. [leadId] must be
  /// the lead's Firestore [Lead.dbId].
  Future<void> deleteWebsiteLead(String leadId) async {
    final response = await _client.delete(
      _uri(ApiConstants.websiteLeadDelete(leadId)),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete website lead');
    }
  }

  /// Deletes every saved website lead in an exact category. Returns the
  /// number of leads deleted.
  Future<int> deleteWebsiteLeadsByCategory(String category) async {
    final response = await _client.delete(
      _uri(
        ApiConstants.websiteLeads,
      ).replace(queryParameters: {'category': category}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to delete website leads');
    }
    return (body['deleted'] as num?)?.toInt() ?? 0;
  }

  /// Deletes a single saved email lead from Firestore. [leadId] must be
  /// the lead's Firestore [Lead.dbId].
  Future<void> deleteEmailLead(String leadId) async {
    final response = await _client.delete(
      _uri(ApiConstants.emailLeadDelete(leadId)),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete email lead');
    }
  }

  /// Deletes every saved email lead in an exact category. Returns the
  /// number of leads deleted.
  Future<int> deleteEmailLeadsByCategory(String category) async {
    final response = await _client.delete(
      _uri(
        ApiConstants.emailLeads,
      ).replace(queryParameters: {'category': category}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to delete email leads');
    }
    return (body['deleted'] as num?)?.toInt() ?? 0;
  }

  /// One page of a lead collection, newest first.
  ///
  /// [cursor] is the previous page's `nextCursor`. [category] is an exact
  /// category; [query] a text search (the backend scans for it, so it can
  /// take several round trips on a big collection — a page may come back
  /// with few results and still have a `nextCursor`). [verifiedOnly] (review
  /// leads), [emailOnly] (website leads) and [sourceType] (WhatsApp leads)
  /// are collection-specific narrowing filters.
  Future<LeadPage> getLeadsPage(
    LeadCollection collection, {
    String? cursor,
    String? category,
    String? query,
    int limit = 50,
    bool verifiedOnly = false,
    bool emailOnly = false,
    String? sourceType,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'cursor': ?cursor,
      'category': ?category,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (verifiedOnly) 'verified': '1',
      if (emailOnly) 'hasEmail': '1',
      'sourceType': ?sourceType,
    };
    final response = await _client.get(_uri(collection.path).replace(queryParameters: params));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load leads');
    }
    return LeadPage.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Distinct categories (with counts) of [collection] — for the category
  /// filter. The backend caches this, so it's cheap after the first call.
  Future<List<LeadCategory>> getLeadCategories(LeadCollection collection) async {
    final response = await _client.get(
      _uri(ApiConstants.dbCategories).replace(queryParameters: {'collection': collection.firestoreName}),
    );
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load categories');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ((body['categories'] as List<dynamic>?) ?? const [])
        .map((e) => LeadCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The dashboard's numbers (computed server-side).
  Future<DashboardOverview> getDashboardOverview() async {
    final response = await _client.get(_uri(ApiConstants.dbOverview));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load the dashboard');
    }
    return DashboardOverview.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Deletes one lead from [collection]. [leadId] is the lead's
  /// [Lead.dbId]. Irreversible.
  Future<void> deleteLeadIn(LeadCollection collection, String leadId) async {
    final response = await _client.delete(_uri('${collection.path}/$leadId'));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete lead');
    }
  }

  /// Deletes every lead of an exact category from [collection]. Returns how
  /// many were deleted. Irreversible.
  Future<int> deleteLeadsInCategory(LeadCollection collection, String category) async {
    final response = await _client.delete(
      _uri(collection.path).replace(queryParameters: {'category': category}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to delete leads');
    }
    return (body['deleted'] as num?)?.toInt() ?? 0;
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
    int concurrency = 10,
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

  /// Starts the state-by-state, city-by-city scan — the sole scan engine
  /// now that the app is US-only. For each category (processed one at a
  /// time), every US state is scanned in order; within the active state,
  /// up to [concurrency] cities are scraped at once. See
  /// `stateCityOrchestrator.js` for the full sequencing.
  Future<void> startStateScan({
    required List<String> categories,
    int concurrency = 10,
    String dateRange = '30',
    int maxResultsPerCity = 160,
    bool analyze = false,
  }) async {
    final response = await _client
        .post(
          _uri(ApiConstants.stateScan),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'categories': categories,
            'concurrency': concurrency,
            'dateRange': dateRange,
            'maxResultsPerCity': maxResultsPerCity,
            'analyze': analyze,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start scan');
    }
  }

  Future<StateCityScanSnapshot> getStateScanStatus() async {
    final response = await _client.get(_uri(ApiConstants.stateScanStatus));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load scan status');
    }
    return StateCityScanSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _postStateScanControl(String path) async {
    final response = await _client.post(_uri(path));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Request failed');
    }
  }

  Future<void> cancelStateScan() => _postStateScanControl(ApiConstants.stateScanCancel);
  Future<void> pauseStateScan() => _postStateScanControl(ApiConstants.stateScanPause);
  Future<void> resumeStateScan() => _postStateScanControl(ApiConstants.stateScanResume);

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
    ).timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start WhatsApp validation');
    }
  }

  /// Same guarded validation job as [startWhatsAppValidation], but for
  /// leads that were never saved to Firestore (e.g. extracted from an
  /// Excel archive) — `id` here is just a correlation key for reading
  /// back [WhatsAppValidationSnapshot.results], not a real document id.
  Future<void> validateExternalLeads(List<Map<String, dynamic>> leads) async {
    final response = await _client.post(
      _uri(ApiConstants.whatsAppWebValidateList),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'leads': leads}),
    ).timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start WhatsApp validation');
    }
  }

  /// Starts the WhatsApp validator over saved leads by Firestore id.
  /// [collection] is `leads` or `websiteLeads`; verified numbers are copied
  /// into the WhatsApp leads collection.
  Future<void> validateSavedLeadWhatsApp(String collection, List<String> ids) async {
    final response = await _client
        .post(
          _uri(ApiConstants.whatsAppWebValidateSaved),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'collection': collection, 'ids': ids}),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start WhatsApp validation');
    }
  }

  Future<void> deleteWhatsAppLead(String leadId) async {
    final response = await _client.delete(_uri(ApiConstants.whatsappLeadDelete(leadId)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete WhatsApp lead');
    }
  }

  Future<void> startWhatsAppAutoValidation({List<String>? states}) async {
    final response = await _client
        .post(
          _uri(ApiConstants.whatsAppWebValidateAuto),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'states': ?states}),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(
        body['error'] ?? 'Failed to start auto WhatsApp validation',
      );
    }
  }

  Future<UnvalidatedWhatsAppSummary> getUnvalidatedWhatsAppSummary() async {
    final response = await _client
        .get(_uri(ApiConstants.whatsAppWebUnvalidated))
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load unvalidated leads');
    }
    return UnvalidatedWhatsAppSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
    return usersJson
        .map((e) => SalesUser.fromJson(e as Map<String, dynamic>))
        .where((u) => u.approved)
        .toList();
  }

  Future<List<SalesUser>> listUsers() async {
    final response = await _client.get(_uri(ApiConstants.users));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load users');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final usersJson = (body['users'] as List<dynamic>? ?? []);
    return usersJson.map((e) => SalesUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<SalesUser> setUserApproved(String id, {required bool approved}) async {
    final response = await _client.patch(
      _uri(ApiConstants.userUpdate(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'approved': approved}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to update user');
    }
    return SalesUser.fromJson(body['user'] as Map<String, dynamic>);
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

  /// Starts the email validation job over an explicit list of businesses
  /// (e.g. extracted from an Excel archive). Each map needs `id` and
  /// `website`; the rest is stored on the `emailLeads` document it creates.
  Future<void> validateEmailLeads(List<Map<String, dynamic>> leads) async {
    final response = await _client
        .post(
          _uri(ApiConstants.emailValidateList),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'leads': leads}),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start email validation');
    }
  }

  /// Starts the email validator over saved leads by Firestore id.
  /// [collection] is `leads` (review leads) or `websiteLeads`. The backend
  /// crawls a lead's site when it has one, otherwise looks the business up
  /// on the web, and skips leads that already have an email.
  Future<void> validateSavedLeadEmails(String collection, List<String> ids) async {
    final response = await _client
        .post(
          _uri(ApiConstants.emailValidateSaved),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'collection': collection, 'ids': ids}),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to start email validation');
    }
  }

  Future<EmailValidationSnapshot> getEmailValidationStatus() async {
    final response = await _client.get(_uri(ApiConstants.emailValidateStatus));
    if (response.statusCode >= 400) {
      throw Exception('Failed to load email validation status');
    }
    return EmailValidationSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> cancelEmailValidation() async {
    final response = await _client.post(_uri(ApiConstants.emailValidateCancel));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to cancel email validation');
    }
  }

  /// Uploads the email-verified businesses (one sheet per category) as an
  /// archive of their own — the email counterpart to
  /// [uploadValidatedArchive].
  Future<ExcelArchive> uploadEmailVerifiedArchive({
    required List<Map<String, dynamic>> sheets,
    String? sourceArchiveId,
    String? sourceFileName,
    List<String>? countries,
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.emailValidatedScans),
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
      throw Exception(body['error'] ?? 'Failed to upload email-verified businesses');
    }
    return ExcelArchive.fromJson(body['archive'] as Map<String, dynamic>);
  }

  Future<List<ExcelArchive>> listEmailVerifiedArchives() async {
    final response = await _client.get(_uri(ApiConstants.emailValidatedScans));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to load email-verified archives');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final archivesJson = (body['archives'] as List<dynamic>? ?? []);
    return archivesJson.map((e) => ExcelArchive.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Lead>> getEmailVerifiedArchiveLeads(String id) async {
    final response = await _client.get(_uri(ApiConstants.emailValidatedLeads(id)));
    if (response.statusCode >= 400) {
      final body = _tryDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to extract leads from archive');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final leadsJson = (body['leads'] as List<dynamic>? ?? []);
    return leadsJson.map((e) => Lead.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteEmailVerifiedArchive(String id) async {
    final response = await _client.delete(_uri(ApiConstants.emailValidatedDelete(id)));
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

  /// Picks a stranded `status: 'partial'` archive back up — e.g. after the
  /// backend crashed/restarted, or the scan was cancelled mid-way. Only
  /// re-scrapes whatever states/countries never finished; already-covered
  /// ones are recovered from the archive's existing workbook, not re-run.
  /// Starts a real scan job and returns which engine picked it up
  /// (`'state-city'` or `'multi-country'`) so the caller knows which live
  /// dashboard to open — the backend infers this from the archive itself,
  /// since two different scan engines can produce a `'partial'` archive.
  Future<String> resumeExcelArchive(String id, {int concurrency = 10}) async {
    final response = await _client.post(
      _uri(ApiConstants.excelArchiveResume(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'concurrency': concurrency}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to resume archive');
    }
    return (body['engine'] as String?) ?? 'state-city';
  }

  Future<Sale> createSale({
    required String businessName,
    String? reviewLink,
    String? salesmanId,
    String? salesmanName,
    LeadStatus leadStatus = LeadStatus.newLead,
    double priceChargedToClient = 0,
    ClientPaymentStatus clientPaymentStatus = ClientPaymentStatus.pending,
    String? clientPaymentMethod,
    double employeePaymentAmount = 0,
    EmployeePaymentStatus employeePaymentStatus = EmployeePaymentStatus.pending,
    double clientAmountReceived = 0,
    double removalCost = 0,
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.sales),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'businessName': businessName,
        'reviewLink': ?reviewLink,
        'salesmanId': ?salesmanId,
        'salesmanName': ?salesmanName,
        'leadStatus': leadStatus.json,
        'priceChargedToClient': priceChargedToClient,
        'clientPaymentStatus': clientPaymentStatus.json,
        'clientPaymentMethod': ?clientPaymentMethod,
        'employeePaymentAmount': employeePaymentAmount,
        'employeePaymentStatus': employeePaymentStatus.json,
        'clientAmountReceived': clientAmountReceived,
        'removalCost': removalCost,
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
    LeadStatus? leadStatus,
    double? priceChargedToClient,
    ClientPaymentStatus? clientPaymentStatus,
    String? clientPaymentMethod,
    double? employeePaymentAmount,
    EmployeePaymentStatus? employeePaymentStatus,
    double? clientAmountReceived,
    double? removalCost,
  }) async {
    final response = await _client.patch(
      _uri(ApiConstants.saleUpdate(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'businessName': ?businessName,
        'reviewLink': ?reviewLink,
        'salesmanId': ?salesmanId,
        'salesmanName': ?salesmanName,
        'leadStatus': ?leadStatus?.json,
        'priceChargedToClient': ?priceChargedToClient,
        'clientPaymentStatus': ?clientPaymentStatus?.json,
        'clientPaymentMethod': ?clientPaymentMethod,
        'employeePaymentAmount': ?employeePaymentAmount,
        'employeePaymentStatus': ?employeePaymentStatus?.json,
        'clientAmountReceived': ?clientAmountReceived,
        'removalCost': ?removalCost,
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

  /// Re-scrapes ongoing and completed sales for 1-star reviews in the last
  /// [dateRange] days. Generous timeout — each business is a real Maps load.
  Future<List<SaleReviewScanResult>> scanSaleReviews({String dateRange = '30', String? salesmanId, bool dedupe = false}) async {
    final response = await _client
        .post(
          _uri(ApiConstants.salesScanReviews),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'dateRange': dateRange,
            'salesmanId': ?salesmanId,
            if (dedupe) 'dedupe': true,
          }),
        )
        .timeout(const Duration(minutes: 20));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Sales review scan failed');
    }
    final resultsJson = (body['results'] as List<dynamic>? ?? []);
    return resultsJson.map((e) => SaleReviewScanResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OutreachDashboard> getOutreachDashboard() async {
    final response = await _client.get(_uri(ApiConstants.outreachDashboard));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load outreach dashboard');
    }
    return OutreachDashboard.fromJson(body);
  }

  Future<OutreachAnalytics> getOutreachAnalytics() async {
    final response = await _client.get(_uri(ApiConstants.outreachAnalytics));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load outreach analytics');
    }
    return OutreachAnalytics.fromJson(body);
  }

  Future<OutreachSettings> getOutreachSettings() async {
    final response = await _client.get(_uri(ApiConstants.outreachSettings));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load outreach settings');
    }
    return OutreachSettings.fromJson(body['settings'] as Map<String, dynamic>?);
  }

  Future<OutreachSettings> updateOutreachSettings(Map<String, dynamic> payload) async {
    final response = await _client.patch(
      _uri(ApiConstants.outreachSettings),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to save outreach settings');
    }
    return OutreachSettings.fromJson(body['settings'] as Map<String, dynamic>?);
  }

  Future<List<OutreachRecord>> listOutreachRecords({
    bool readyForReview = false,
    String? campaignId,
    String? outreachStatus,
    String? sourceCollection,
  }) async {
    final params = <String, String>{
      if (readyForReview) 'readyForReview': 'true',
      'campaignId': ?campaignId,
      'outreachStatus': ?outreachStatus,
      'sourceCollection': ?sourceCollection,
      'limit': '200',
    };
    final response = await _client.get(_uri(ApiConstants.outreachRecords).replace(queryParameters: params));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load outreach records');
    }
    return (body['records'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => OutreachRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<OutreachRecord> ensureOutreachRecord({
    required String sourceCollection,
    required String sourceLeadId,
    String? campaignId,
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.outreachRecords),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sourceCollection': sourceCollection,
        'sourceLeadId': sourceLeadId,
        'campaignId': ?campaignId,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to open outreach record');
    }
    return OutreachRecord.fromJson(body['record'] as Map<String, dynamic>);
  }

  Future<(OutreachRecord, List<OutreachEvent>)> getOutreachRecord(String id) async {
    final response = await _client.get(_uri(ApiConstants.outreachRecord(id)));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load outreach record');
    }
    final record = OutreachRecord.fromJson(body['record'] as Map<String, dynamic>);
    final events = (body['events'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => OutreachEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (record, events);
  }

  Future<OutreachRecord> _postRecord(String path, {Map<String, dynamic>? payload}) async {
    final response = await _client
        .post(
          _uri(path),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload ?? const {}),
        )
        .timeout(const Duration(minutes: 2));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Outreach request failed');
    }
    final recordJson = body['record'] as Map<String, dynamic>? ?? body;
    return OutreachRecord.fromJson(recordJson);
  }

  Future<OutreachRecord> updateOutreachRecord(String id, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      _uri(ApiConstants.outreachRecord(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to update outreach record');
    }
    return OutreachRecord.fromJson(body['record'] as Map<String, dynamic>);
  }

  Future<OutreachRecord> outreachDiscoverEmail(String id, {bool force = false}) =>
      _postRecord(ApiConstants.outreachRecordDiscover(id), payload: {'force': force});

  Future<OutreachRecord> outreachVerifyEmail(String id, {bool force = false}) =>
      _postRecord(ApiConstants.outreachRecordVerify(id), payload: {'force': force});

  Future<OutreachRecord> outreachAnalyzeWebsite(String id, {bool force = false}) =>
      _postRecord(ApiConstants.outreachRecordAnalyze(id), payload: {'force': force});

  Future<OutreachRecord> outreachGenerateEmail(String id, {bool force = false}) =>
      _postRecord(ApiConstants.outreachRecordGenerate(id), payload: {'force': force});

  Future<OutreachRecord> outreachProcessLead(String id, {bool force = false, bool autoSend = false}) =>
      _postRecord(ApiConstants.outreachRecordProcess(id), payload: {'force': force, 'autoSend': autoSend});

  Future<OutreachRecord> outreachApprove(String id, {String? subject, String? body}) =>
      _postRecord(ApiConstants.outreachRecordApprove(id), payload: {
        'subject': ?subject,
        'body': ?body,
      });

  Future<OutreachRecord> outreachReject(String id) =>
      _postRecord(ApiConstants.outreachRecordReject(id));

  Future<OutreachRecord> outreachSetStatus(String id, String status) =>
      _postRecord(ApiConstants.outreachRecordStatus(id), payload: {'outreachStatus': status});

  Future<List<OutreachCampaign>> listOutreachCampaigns() async {
    final response = await _client.get(_uri(ApiConstants.outreachCampaigns));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load campaigns');
    }
    return (body['campaigns'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => OutreachCampaign.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<OutreachCampaign> createOutreachCampaign(Map<String, dynamic> payload) async {
    final response = await _client.post(
      _uri(ApiConstants.outreachCampaigns),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to create campaign');
    }
    return OutreachCampaign.fromJson(body['campaign'] as Map<String, dynamic>);
  }

  Future<OutreachCampaign> updateOutreachCampaign(String id, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      _uri(ApiConstants.outreachCampaign(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to update campaign');
    }
    return OutreachCampaign.fromJson(body['campaign'] as Map<String, dynamic>);
  }

  Future<void> startOutreachCampaign(String id) async {
    final response = await _client.post(
      _uri(ApiConstants.outreachCampaignStart(id)),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to start campaign');
    }
  }

  Future<OutreachJob> startOutreachRun({
    required String kind,
    required int from,
    required int to,
    String sourceCollection = 'websiteLeads',
  }) async {
    final response = await _client.post(
      _uri(ApiConstants.outreachRun),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'kind': kind,
        'from': from,
        'to': to,
        'sourceCollection': sourceCollection,
      }),
    );
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to start outreach');
    }
    return OutreachJob.fromJson(body['job'] as Map<String, dynamic>?);
  }

  Future<OutreachJob> getOutreachJob() async {
    final response = await _client.get(_uri(ApiConstants.outreachJob));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to load outreach job');
    }
    return OutreachJob.fromJson(body['job'] as Map<String, dynamic>?);
  }

  Future<OutreachJob> cancelOutreachJob() async {
    final response = await _client.post(_uri(ApiConstants.outreachJobCancel));
    final body = _tryDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception(body['error'] ?? 'Failed to cancel outreach job');
    }
    return OutreachJob.fromJson(body['job'] as Map<String, dynamic>?);
  }

  Map<String, dynamic> _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
