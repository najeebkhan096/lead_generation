import 'package:equatable/equatable.dart';

import 'job_application.dart';
import 'job_json.dart';
import 'job_scan.dart';

class JobStats extends Equatable {
  const JobStats({
    this.total = 0,
    this.active = 0,
    this.expired = 0,
    this.unseen = 0,
    this.discoveredLast24h = 0,
    this.companies = 0,
    this.applications = 0,
    this.applicationsByStage = const {},
    this.lastScan,
    this.scansCompleted = 0,
    this.scansFailed = 0,
    this.scansStopped = 0,
    this.successRate,
  });

  factory JobStats.fromJson(Map<String, dynamic> j) {
    final jobs = jobMap(j['jobs']);
    final apps = jobMap(j['applications']);
    final scans = jobMap(j['scans']);
    final byStage = jobMap(apps['byStage']);
    return JobStats(
      total: jobInt(jobs['total']) ?? 0,
      active: jobInt(jobs['active']) ?? 0,
      expired: jobInt(jobs['expired']) ?? 0,
      unseen: jobInt(jobs['unseen']) ?? 0,
      discoveredLast24h: jobInt(jobs['discoveredLast24h']) ?? 0,
      companies: jobInt(j['companies']) ?? 0,
      applications: jobInt(apps['total']) ?? 0,
      applicationsByStage: {
        for (final s in ApplicationStage.values) s: jobInt(byStage[s.wire]) ?? 0,
      },
      lastScan: j['lastScan'] is Map ? JobScan.fromJson(jobMap(j['lastScan'])) : null,
      scansCompleted: jobInt(scans['completed']) ?? 0,
      scansFailed: jobInt(scans['failed']) ?? 0,
      scansStopped: jobInt(scans['stopped']) ?? 0,
      successRate: jobInt(scans['successRate']),
    );
  }

  final int total;
  final int active;
  final int expired;

  /// Jobs nobody has triaged yet (not saved, applied or rejected).
  final int unseen;
  final int discoveredLast24h;
  final int companies;
  final int applications;
  final Map<ApplicationStage, int> applicationsByStage;
  final JobScan? lastScan;
  final int scansCompleted;
  final int scansFailed;
  final int scansStopped;
  final int? successRate;

  int get scansFinished => scansCompleted + scansFailed + scansStopped;

  @override
  List<Object?> get props => [total, active, expired, unseen, discoveredLast24h, companies, applications, applicationsByStage, lastScan, scansCompleted, scansFailed, scansStopped, successRate];
}
