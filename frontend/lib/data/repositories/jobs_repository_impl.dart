import 'dart:typed_data';

import '../../domain/entities/job.dart';
import '../../domain/entities/job_application.dart';
import '../../domain/entities/job_filters.dart';
import '../../domain/entities/job_geo.dart';
import '../../domain/entities/job_scan.dart';
import '../../domain/entities/job_search.dart';
import '../../domain/entities/job_source_info.dart';
import '../../domain/entities/job_stats.dart';
import '../../domain/entities/paged.dart';
import '../../domain/repositories/jobs_repository.dart';
import '../datasources/jobs_remote_datasource.dart';

/// [JobsRepository] over HTTP. The geography is static, so it is read once per
/// session and kept: the country list, each country's regions, and each
/// region's cities (the first, unfiltered slice).
class JobsRepositoryImpl implements JobsRepository {
  JobsRepositoryImpl(this._remote);

  final JobsRemoteDataSource _remote;

  List<JobCountry>? _countries;
  final Map<String, List<JobRegion>> _regions = {};
  final Map<String, JobCityList> _cities = {};

  @override
  Future<List<JobCountry>> countries() async => _countries ??= await _remote.countries();

  @override
  Future<List<JobRegion>> regions(String countryCode) async => _regions[countryCode] ??= await _remote.regions(countryCode);

  @override
  Future<JobCityList> cities(String countryCode, String region, {String? query, int limit = 500, int offset = 0}) async {
    final cacheable = (query == null || query.trim().isEmpty) && offset == 0 && limit == 500;
    final key = '$countryCode|$region';
    if (cacheable && _cities.containsKey(key)) return _cities[key]!;
    final result = await _remote.cities(countryCode, region, query: query, limit: limit, offset: offset);
    if (cacheable) _cities[key] = result;
    return result;
  }

  Future<Map<String, String>> _names() async => {for (final c in await countries()) c.code: c.name};

  @override
  Future<List<JobSourceInfo>> sources() => _remote.sources();

  @override
  Future<JobSourceInfo> updateSource(String id, {bool? enabled, JobSourceLimits? limits, List<String>? boards, List<JobCareerPage>? careerPages}) =>
      _remote.updateSource(id, enabled: enabled, limits: limits, boards: boards, careerPages: careerPages);

  @override
  Future<Paged<JobSearch>> searches({String? cursor}) async => _remote.searches(cursor: cursor, countryNames: await _names());

  @override
  Future<JobSearch> createSearch(JobSearch search) async => _remote.createSearch(search, countryNames: await _names());

  @override
  Future<JobSearch> updateSearch(JobSearch search) async => _remote.updateSearch(search, countryNames: await _names());

  @override
  Future<void> deleteSearch(String id) => _remote.deleteSearch(id);

  @override
  Future<JobEstimate> estimate(JobSearch draft) => _remote.estimate(draft);

  @override
  Future<JobScan> startScan(String searchId) => _remote.startScan(searchId);

  @override
  Future<JobScan> scan(String runId) => _remote.scan(runId);

  @override
  Future<JobScan> pauseScan(String runId) => _remote.pauseScan(runId);

  @override
  Future<JobScan> resumeScan(String runId) => _remote.resumeScan(runId);

  @override
  Future<JobScan> stopScan(String runId) => _remote.stopScan(runId);

  @override
  Future<List<JobScan>> activeScans() => _remote.activeScans();

  @override
  Future<Paged<JobScan>> scanHistory({String? cursor, String? searchId}) => _remote.scanHistory(cursor: cursor, searchId: searchId);

  @override
  Future<List<JobScanFailure>> scanFailures(String runId) => _remote.scanFailures(runId);

  @override
  Future<Paged<Job>> jobs(JobFilters filters, {String? cursor, int limit = 25}) => _remote.jobs(filters, cursor: cursor, limit: limit);

  @override
  Future<Job> job(String id) => _remote.job(id);

  @override
  Future<Job> setJobStatus(String id, String status) => _remote.patchJob(id, {'status': status});

  @override
  Future<Job> saveJobNotes(String id, String notes) => _remote.patchJob(id, {'notes': notes});

  @override
  Future<void> deleteJob(String id) => _remote.deleteJob(id);

  @override
  Future<Job> verifyJob(String id) => _remote.verifyJob(id);

  @override
  Future<JobMatch> matchJob(String id, String cvText) => _remote.matchJob(id, cvText);

  @override
  Future<Uint8List> exportJobs(JobFilters filters) => _remote.exportJobs(filters);

  @override
  Future<Uint8List> exportSelectedJobs(List<String> ids) => _remote.exportSelectedJobs(ids);

  @override
  Future<Paged<JobCompany>> companies({String? cursor, String? query}) => _remote.companies(cursor: cursor, query: query);

  @override
  Future<JobStats> stats({bool refresh = false}) => _remote.stats(refresh: refresh);

  @override
  Future<Paged<JobApplication>> applications({ApplicationStage? stage, String? cursor, int limit = 25}) =>
      _remote.applications(stage: stage, cursor: cursor, limit: limit);

  @override
  Future<Map<ApplicationStage, int>> applicationSummary() => _remote.applicationSummary();

  @override
  Future<JobApplication> saveApplication(String jobId, {ApplicationStage? stage, String? notes}) =>
      _remote.saveApplication(jobId, stage: stage, notes: notes);

  @override
  Future<void> removeApplication(String jobId) => _remote.removeApplication(jobId);

  @override
  Future<Paged<JobAlert>> alerts() => _remote.alerts();

  @override
  Future<JobAlert> createAlert(String name, Map<String, dynamic> filters) => _remote.createAlert(name, filters);

  @override
  Future<void> deleteAlert(String id) => _remote.deleteAlert(id);
}
