import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../domain/entities/job.dart';
import '../../domain/entities/job_application.dart';
import '../../domain/entities/job_filters.dart';
import '../../domain/entities/job_geo.dart';
import '../../domain/entities/job_json.dart';
import '../../domain/entities/job_scan.dart';
import '../../domain/entities/job_search.dart';
import '../../domain/entities/job_source_info.dart';
import '../../domain/entities/job_stats.dart';
import '../../domain/entities/paged.dart';

/// An error answer from the Jobs API, with the server's message (which is
/// written to be shown) and, for validation failures, each field's problem.
class JobsApiException implements Exception {
  const JobsApiException(this.message, {this.status = 0, this.code, this.details = const []});

  final String message;
  final int status;
  final String? code;
  final List<Map<String, dynamic>> details;

  /// "name: is required · titles: needs at least one entry".
  String get detailed => details.isEmpty ? message : details.map((d) => '${d['field']}: ${d['message']}').join(' · ');

  bool get isConflict => status == 409;

  @override
  String toString() => message;
}

/// Talks to `/api/jobs` and turns the JSON into entities.
class JobsRemoteDataSource {
  JobsRemoteDataSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) {
    var base = ApiConstants.baseUrl.trim();
    final full = '${ApiConstants.jobs}$path';
    if (base.isEmpty) {
      if (kIsWeb && Uri.base.host != 'localhost' && Uri.base.host != '127.0.0.1') {
        base = 'http://localhost:3001';
      } else {
        return Uri.parse(full).replace(queryParameters: query?.isEmpty ?? true ? null : query);
      }
    }
    return Uri.parse('$base$full').replace(queryParameters: query?.isEmpty ?? true ? null : query);
  }

  Never _fail(http.Response r) {
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {/* not JSON */}
    final fallback = switch (r.statusCode) {
      429 => 'Too many requests — wait a moment and try again.',
      >= 500 => 'The server had a problem (${r.statusCode}).',
      _ => 'Request failed (${r.statusCode}).',
    };
    throw JobsApiException(
      (body['error'] as String?) ?? fallback,
      status: r.statusCode,
      code: body['code'] as String?,
      details: jobMaps(body['details']),
    );
  }

  Future<http.Response> _raw(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = _uri(path, query);
    final headers = {if (body != null) 'content-type': 'application/json'};
    final payload = body == null ? null : jsonEncode(body);
    try {
      final r = switch (method) {
        'GET' => await _client.get(uri),
        'POST' => await _client.post(uri, headers: headers, body: payload),
        'PUT' => await _client.put(uri, headers: headers, body: payload),
        'PATCH' => await _client.patch(uri, headers: headers, body: payload),
        'DELETE' => await _client.delete(uri),
        _ => throw ArgumentError(method),
      };
      if (r.statusCode >= 400) _fail(r);
      return r;
    } on JobsApiException {
      rethrow;
    } catch (e) {
      throw const JobsApiException('Could not reach the server. Is the backend running?');
    }
  }

  Future<Map<String, dynamic>> _json(String method, String path, {Object? body, Map<String, String>? query}) async {
    final r = await _raw(method, path, body: body, query: query);
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }

  Paged<T> _page<T>(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) => Paged(
        items: [for (final m in jobMaps(j['items'])) parse(m)],
        nextCursor: jobString(j['nextCursor']),
        total: jobInt(j['total']),
      );

  // ------------------------------------------------------------------ geo
  Future<List<JobCountry>> countries() async => [for (final c in jobMaps((await _json('GET', '/geo/countries'))['countries'])) JobCountry.fromJson(c)];

  Future<List<JobRegion>> regions(String code) async =>
      [for (final r in jobMaps((await _json('GET', '/geo/countries/${Uri.encodeComponent(code)}/regions'))['regions'])) JobRegion.fromJson(r)];

  Future<JobCityList> cities(String code, String region, {String? query, int limit = 500, int offset = 0}) async {
    final j = await _json('GET', '/geo/countries/${Uri.encodeComponent(code)}/regions/${Uri.encodeComponent(region)}/cities', query: {
      'limit': '$limit',
      'offset': '$offset',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    return JobCityList(cities: [for (final c in jobMaps(j['cities'])) JobCity.fromJson(c)], total: jobInt(j['total']) ?? 0);
  }

  // -------------------------------------------------------------- sources
  Future<List<JobSourceInfo>> sources() async => [for (final s in jobMaps((await _json('GET', '/sources'))['sources'])) JobSourceInfo.fromJson(s)];

  Future<JobSourceInfo> updateSource(String id, {bool? enabled, JobSourceLimits? limits, List<String>? boards, List<JobCareerPage>? careerPages}) async {
    final body = <String, dynamic>{
      'enabled': ?enabled,
      if (limits != null) 'limits': {'perMinute': limits.perMinute, 'perDay': limits.perDay, 'maxConcurrent': limits.maxConcurrent},
      if (boards != null || careerPages != null)
        'settings': {
          if (boards != null) 'boards': [for (final b in boards) {'id': b}],
          if (careerPages != null) 'careerPages': [for (final c in careerPages) c.toJson()],
        },
    };
    return JobSourceInfo.fromJson(jobMap((await _json('PATCH', '/sources/${Uri.encodeComponent(id)}', body: body))['source']));
  }

  // ------------------------------------------------------------- searches
  Future<Paged<JobSearch>> searches({String? cursor, Map<String, String> countryNames = const {}}) async =>
      _page(await _json('GET', '/searches', query: {'limit': '50', 'cursor': ?cursor}), (m) => JobSearch.fromJson(m, countryNames: countryNames));

  Future<JobSearch> createSearch(JobSearch s, {Map<String, String> countryNames = const {}}) async =>
      JobSearch.fromJson(jobMap((await _json('POST', '/searches', body: s.toJson()))['search']), countryNames: countryNames);

  Future<JobSearch> updateSearch(JobSearch s, {Map<String, String> countryNames = const {}}) async =>
      JobSearch.fromJson(jobMap((await _json('PUT', '/searches/${s.id}', body: s.toJson()))['search']), countryNames: countryNames);

  Future<void> deleteSearch(String id) async => _json('DELETE', '/searches/$id');

  Future<JobEstimate> estimate(JobSearch draft) async => JobEstimate.fromJson(await _json('POST', '/searches/estimate', body: draft.toJson()));

  // ---------------------------------------------------------------- scans
  Future<JobScan> startScan(String searchId) async => JobScan.fromJson(jobMap((await _json('POST', '/searches/$searchId/scan'))['run']));

  Future<JobScan> scan(String runId) async => JobScan.fromJson(jobMap((await _json('GET', '/scans/$runId'))['run']));

  Future<JobScan> pauseScan(String runId) async => JobScan.fromJson(jobMap((await _json('POST', '/scans/$runId/pause'))['run']));

  Future<JobScan> resumeScan(String runId) async => JobScan.fromJson(jobMap((await _json('POST', '/scans/$runId/resume'))['run']));

  Future<JobScan> stopScan(String runId) async => JobScan.fromJson(jobMap((await _json('POST', '/scans/$runId/stop'))['run']));

  Future<List<JobScan>> activeScans() async => [for (final r in jobMaps((await _json('GET', '/scans/active'))['runs'])) JobScan.fromJson(r)];

  Future<Paged<JobScan>> scanHistory({String? cursor, String? searchId}) async =>
      _page(await _json('GET', '/scans', query: {'limit': '20', 'cursor': ?cursor, 'searchId': ?searchId}), JobScan.fromJson);

  Future<List<JobScanFailure>> scanFailures(String runId) async =>
      [for (final f in jobMaps((await _json('GET', '/scans/$runId/failures'))['failures'])) JobScanFailure.fromJson(f)];

  // ----------------------------------------------------------------- jobs
  Future<Paged<Job>> jobs(JobFilters filters, {String? cursor, int limit = 25}) async =>
      _page(await _json('GET', '/jobs', query: {...filters.toQuery(), 'limit': '$limit', 'cursor': ?cursor}), Job.fromJson);

  Future<Job> job(String id) async => Job.fromJson(jobMap((await _json('GET', '/jobs/${Uri.encodeComponent(id)}'))['job']));

  Future<Job> patchJob(String id, Map<String, dynamic> body) async =>
      Job.fromJson(jobMap((await _json('PATCH', '/jobs/${Uri.encodeComponent(id)}', body: body))['job']));

  Future<void> deleteJob(String id) async => _json('DELETE', '/jobs/${Uri.encodeComponent(id)}');

  Future<Job> verifyJob(String id) async => Job.fromJson(jobMap((await _json('POST', '/jobs/${Uri.encodeComponent(id)}/verify'))['job']));

  Future<JobMatch> matchJob(String id, String cvText) async =>
      JobMatch.fromJson(jobMap((await _json('POST', '/jobs/${Uri.encodeComponent(id)}/match', body: {'cvText': cvText}))['match']));

  Future<Uint8List> exportJobs(JobFilters filters) async => (await _raw('GET', '/jobs/export.csv', query: filters.toQuery())).bodyBytes;

  Future<Uint8List> exportSelectedJobs(List<String> ids) async => (await _raw('POST', '/jobs/export', body: {'ids': ids})).bodyBytes;

  // ------------------------------------------------- companies and stats
  Future<Paged<JobCompany>> companies({String? cursor, String? query}) async =>
      _page(await _json('GET', '/companies', query: {'limit': '50', 'cursor': ?cursor, 'q': ?query}), JobCompany.fromJson);

  Future<JobStats> stats({bool refresh = false}) async => JobStats.fromJson(await _json('GET', '/stats', query: {if (refresh) 'refresh': '1'}));

  // --------------------------------------------------------- applications
  Future<Paged<JobApplication>> applications({ApplicationStage? stage, String? cursor, int limit = 25}) async =>
      _page(await _json('GET', '/applications', query: {'limit': '$limit', 'stage': ?stage?.wire, 'cursor': ?cursor}), JobApplication.fromJson);

  Future<Map<ApplicationStage, int>> applicationSummary() async {
    final byStage = jobMap((await _json('GET', '/applications/summary'))['byStage']);
    return {for (final s in ApplicationStage.values) s: jobInt(byStage[s.wire]) ?? 0};
  }

  Future<JobApplication> saveApplication(String jobId, {ApplicationStage? stage, String? notes}) async => JobApplication.fromJson(jobMap((await _json(
        'PUT',
        '/applications/${Uri.encodeComponent(jobId)}',
        body: {'stage': ?stage?.wire, 'notes': ?notes},
      ))['application']));

  Future<void> removeApplication(String jobId) async => _json('DELETE', '/applications/${Uri.encodeComponent(jobId)}');

  // --------------------------------------------------------------- alerts
  Future<Paged<JobAlert>> alerts() async => _page(await _json('GET', '/alerts', query: {'limit': '50'}), JobAlert.fromJson);

  Future<JobAlert> createAlert(String name, Map<String, dynamic> filters) async =>
      JobAlert.fromJson(jobMap((await _json('POST', '/alerts', body: {'name': name, 'filters': filters}))['alert']));

  Future<void> deleteAlert(String id) async => _json('DELETE', '/alerts/$id');
}
