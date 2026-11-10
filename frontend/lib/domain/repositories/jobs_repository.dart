import 'dart:typed_data';

import '../entities/job.dart';
import '../entities/job_application.dart';
import '../entities/job_filters.dart';
import '../entities/job_geo.dart';
import '../entities/job_scan.dart';
import '../entities/job_search.dart';
import '../entities/job_source_info.dart';
import '../entities/job_stats.dart';
import '../entities/paged.dart';

/// Everything the Jobs Finder screens need from the backend (`/api/jobs`).
abstract class JobsRepository {
  // ---- geography (static data: cached after the first read)
  Future<List<JobCountry>> countries();
  Future<List<JobRegion>> regions(String countryCode);
  Future<JobCityList> cities(String countryCode, String region, {String? query, int limit = 500, int offset = 0});

  // ---- sources
  Future<List<JobSourceInfo>> sources();
  Future<JobSourceInfo> updateSource(String id, {bool? enabled, JobSourceLimits? limits, List<String>? boards, List<JobCareerPage>? careerPages});

  // ---- saved searches
  Future<Paged<JobSearch>> searches({String? cursor});
  Future<JobSearch> createSearch(JobSearch search);
  Future<JobSearch> updateSearch(JobSearch search);
  Future<void> deleteSearch(String id);
  Future<JobEstimate> estimate(JobSearch draft);

  // ---- scans
  Future<JobScan> startScan(String searchId);
  Future<JobScan> scan(String runId);
  Future<JobScan> pauseScan(String runId);
  Future<JobScan> resumeScan(String runId);
  Future<JobScan> stopScan(String runId);
  Future<List<JobScan>> activeScans();
  Future<Paged<JobScan>> scanHistory({String? cursor, String? searchId});
  Future<List<JobScanFailure>> scanFailures(String runId);

  // ---- jobs
  Future<Paged<Job>> jobs(JobFilters filters, {String? cursor, int limit = 25});
  Future<Job> job(String id);
  Future<Job> setJobStatus(String id, String status);
  Future<Job> saveJobNotes(String id, String notes);
  Future<void> deleteJob(String id);
  Future<Job> verifyJob(String id);
  Future<JobMatch> matchJob(String id, String cvText);
  Future<Uint8List> exportJobs(JobFilters filters);
  Future<Uint8List> exportSelectedJobs(List<String> ids);

  // ---- companies and statistics
  Future<Paged<JobCompany>> companies({String? cursor, String? query});
  Future<JobStats> stats({bool refresh = false});

  // ---- application tracker
  Future<Paged<JobApplication>> applications({ApplicationStage? stage, String? cursor, int limit = 25});
  Future<Map<ApplicationStage, int>> applicationSummary();
  Future<JobApplication> saveApplication(String jobId, {ApplicationStage? stage, String? notes});
  Future<void> removeApplication(String jobId);

  // ---- alerts
  Future<Paged<JobAlert>> alerts();
  Future<JobAlert> createAlert(String name, Map<String, dynamic> filters);
  Future<void> deleteAlert(String id);
}
