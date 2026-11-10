import 'dart:typed_data';

import 'package:lead_generation_app/data/datasources/jobs_remote_datasource.dart';
import 'package:lead_generation_app/domain/entities/job.dart';
import 'package:lead_generation_app/domain/entities/job_application.dart';
import 'package:lead_generation_app/domain/entities/job_filters.dart';
import 'package:lead_generation_app/domain/entities/job_geo.dart';
import 'package:lead_generation_app/domain/entities/job_scan.dart';
import 'package:lead_generation_app/domain/entities/job_search.dart';
import 'package:lead_generation_app/domain/entities/job_source_info.dart';
import 'package:lead_generation_app/domain/entities/job_stats.dart';
import 'package:lead_generation_app/domain/entities/paged.dart';
import 'package:lead_generation_app/domain/repositories/jobs_repository.dart';

/// A job as the API would send it (list shape).
Job fakeJob(String id, {String? title, String company = 'Acme', Map<String, dynamic> extra = const {}}) => Job.fromJson({
      'id': id,
      'title': title ?? 'Flutter Developer $id',
      'companyName': company,
      'city': 'Los Angeles',
      'state': 'California',
      'country': 'United States',
      'countryCode': 'US',
      'requiredSkills': ['Flutter', 'Dart'],
      'sourceNames': ['greenhouse'],
      'sourceUrl': 'https://boards.example/$id',
      'status': 'active',
      'userState': 'new',
      'discoveredAt': '2026-11-06T10:00:00Z',
      ...extra,
    });

Map<String, dynamic> scanJson(String id, {String status = 'running', int done = 2, int total = 10, String name = 'Flutter in CA'}) => {
      'id': id,
      'searchId': 's1',
      'searchName': name,
      'status': status,
      'totals': {'combinations': total, 'completed': done, 'failed': 0, 'skipped': 0, 'pending': total - done, 'running': 1},
      'percent': done / total * 100,
      'jobs': {'found': 20, 'new': 15, 'updated': 2, 'duplicate': 3},
      'sources': {
        'greenhouse': {'state': 'ready', 'requests': 4, 'found': 20, 'new': 15, 'errors': 0},
        'adzuna': {'state': 'not_configured', 'requests': 0, 'found': 0, 'errors': 0},
      },
      'current': [
        {'country': 'United States', 'state': 'California', 'city': 'Los Angeles', 'title': 'Flutter Developer'},
      ],
      'recentErrors': [],
      'startedAt': '2026-11-07T10:00:00Z',
      'finishedAt': status == 'completed' ? '2026-11-07T10:05:00Z' : null,
    };

/// Only what the screens under test call is implemented; anything else fails
/// loudly through [noSuchMethod].
class FakeJobsRepository implements JobsRepository {
  FakeJobsRepository({List<Job>? jobs}) : jobsData = jobs ?? [];

  List<Job> jobsData;
  final jobQueries = <({JobFilters filters, String? cursor, int limit})>[];
  bool failJobs = false;
  Duration Function(JobFilters)? jobDelay;

  final actions = <String>[];
  Object? actionError;

  // scans
  List<JobScan> activeData = [];
  Paged<JobScan> historyData = const Paged(items: []);
  Object? startError;
  int activeCalls = 0;

  // geography
  List<JobCountry> countriesData = const [
    JobCountry(code: 'US', name: 'United States', adminLabel: 'State', regionCount: 3, cityCount: 6),
    JobCountry(code: 'QA', name: 'Qatar', adminLabel: 'Municipality', regionCount: 1, cityCount: 1),
    JobCountry(code: 'WW', name: 'Worldwide / Remote', remoteOnly: true),
  ];
  final regionsData = <String, List<JobRegion>>{
    'US': const [JobRegion(code: 'CA', name: 'California', cityCount: 3), JobRegion(code: 'TX', name: 'Texas', cityCount: 2), JobRegion(code: 'NY', name: 'New York', cityCount: 1)],
    'QA': const [JobRegion(code: '01', name: 'Doha', cityCount: 1)],
  };
  final citiesData = <String, List<JobCity>>{
    'US|California': const [JobCity(name: 'Los Angeles', population: 3800000), JobCity(name: 'San Diego', population: 1400000), JobCity(name: 'San Francisco', population: 800000)],
    'US|Texas': const [JobCity(name: 'Houston', population: 2300000), JobCity(name: 'Austin', population: 950000)],
  };

  // searches
  List<JobSearch> savedSearches = [];
  final estimates = <JobSearch>[];
  JobEstimate estimateResult = const JobEstimate(locations: 3, titles: 1, combinations: 3, usableSources: ['greenhouse']);
  Object? saveError;

  // tracker
  Map<ApplicationStage, List<JobApplication>> applicationsData = {};

  @override
  Future<List<JobCountry>> countries() async => countriesData;

  @override
  Future<List<JobRegion>> regions(String countryCode) async => regionsData[countryCode] ?? const [];

  @override
  Future<JobCityList> cities(String countryCode, String region, {String? query, int limit = 500, int offset = 0}) async {
    final all = citiesData['$countryCode|$region'] ?? const <JobCity>[];
    return JobCityList(cities: all, total: all.length);
  }

  @override
  Future<List<JobSourceInfo>> sources() async => const [
        JobSourceInfo(id: 'greenhouse', name: 'Greenhouse', type: 'ats', boards: ['airbnb']),
        JobSourceInfo(id: 'adzuna', name: 'Adzuna', requiresKey: true, configured: false, configurationHint: 'Set ADZUNA_APP_ID and ADZUNA_APP_KEY.'),
      ];

  // ---- jobs
  @override
  Future<Paged<Job>> jobs(JobFilters filters, {String? cursor, int limit = 25}) async {
    jobQueries.add((filters: filters, cursor: cursor, limit: limit));
    final delay = jobDelay?.call(filters);
    if (delay != null) await Future<void>.delayed(delay);
    if (failJobs) throw const JobsApiException('Could not reach the server.');
    bool matches(Job j) {
      if (filters.view == JobView.active && j.status != 'active') return false;
      if (filters.view == JobView.newJobs && (j.userState != 'new' || j.status != 'active')) return false;
      if (filters.view == JobView.saved && j.userState != 'saved') return false;
      if (filters.view == JobView.expired && j.status == 'active') return false;
      final q = filters.query?.toLowerCase();
      if (q != null && !j.title.toLowerCase().contains(q)) return false;
      if (filters.city != null && j.city != filters.city) return false;
      return true;
    }

    final all = jobsData.where(matches).toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + limit).clamp(0, all.length);
    return Paged(items: all.sublist(start, end), nextCursor: end < all.length ? '$end' : null, total: cursor == null ? all.length : null);
  }

  @override
  Future<Job> job(String id) async => jobsData.firstWhere((j) => j.id == id);

  @override
  Future<Job> setJobStatus(String id, String status) async {
    if (actionError != null) throw actionError!;
    actions.add('status:$id:$status');
    return jobsData.firstWhere((j) => j.id == id).copyWith(status: status);
  }

  @override
  Future<void> deleteJob(String id) async {
    if (actionError != null) throw actionError!;
    actions.add('delete:$id');
    jobsData = jobsData.where((j) => j.id != id).toList();
  }

  @override
  Future<JobApplication> saveApplication(String jobId, {ApplicationStage? stage, String? notes}) async {
    if (actionError != null) throw actionError!;
    actions.add('app:$jobId:${stage?.wire}');
    return JobApplication(jobId: jobId, stage: stage ?? ApplicationStage.saved, notes: notes ?? '');
  }

  @override
  Future<void> removeApplication(String jobId) async {
    if (actionError != null) throw actionError!;
    actions.add('unapp:$jobId');
  }

  @override
  Future<Uint8List> exportSelectedJobs(List<String> ids) async => Uint8List.fromList('csv'.codeUnits);

  // ---- scans
  @override
  Future<List<JobScan>> activeScans() async {
    activeCalls++;
    return activeData;
  }

  @override
  Future<Paged<JobScan>> scanHistory({String? cursor, String? searchId}) async => historyData;

  @override
  Future<List<JobScanFailure>> scanFailures(String runId) async => const [];

  @override
  Future<JobScan> startScan(String searchId) async {
    if (startError != null) throw startError!;
    actions.add('start:$searchId');
    final run = JobScan.fromJson(scanJson('run-1'));
    activeData = [run];
    return run;
  }

  @override
  Future<JobScan> pauseScan(String runId) async {
    actions.add('pause:$runId');
    activeData = [JobScan.fromJson(scanJson(runId, status: 'paused'))];
    return activeData.first;
  }

  @override
  Future<JobScan> resumeScan(String runId) async {
    actions.add('resume:$runId');
    activeData = [JobScan.fromJson(scanJson(runId))];
    return activeData.first;
  }

  @override
  Future<JobScan> stopScan(String runId) async {
    actions.add('stop:$runId');
    activeData = [JobScan.fromJson(scanJson(runId, status: 'stopping'))];
    return activeData.first;
  }

  // ---- searches
  @override
  Future<Paged<JobSearch>> searches({String? cursor}) async => Paged(items: savedSearches);

  @override
  Future<JobEstimate> estimate(JobSearch draft) async {
    estimates.add(draft);
    return estimateResult;
  }

  @override
  Future<JobSearch> createSearch(JobSearch search) async {
    if (saveError != null) throw saveError!;
    final stored = search.copyWith();
    return JobSearch.fromJson({...stored.toJson(), 'id': 's-new'});
  }

  @override
  Future<JobSearch> updateSearch(JobSearch search) async => search;

  @override
  Future<void> deleteSearch(String id) async => actions.add('deleteSearch:$id');

  // ---- tracker
  @override
  Future<Map<ApplicationStage, int>> applicationSummary() async => {for (final s in ApplicationStage.values) s: applicationsData[s]?.length ?? 0};

  @override
  Future<Paged<JobApplication>> applications({ApplicationStage? stage, String? cursor, int limit = 25}) async => Paged(items: applicationsData[stage] ?? const []);

  @override
  Future<JobStats> stats({bool refresh = false}) async => const JobStats(total: 1240, active: 1100, expired: 140, unseen: 300, companies: 85, applications: 12);

  @override
  Future<Paged<JobAlert>> alerts() async => const Paged(items: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
