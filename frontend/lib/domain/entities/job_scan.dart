import 'package:equatable/equatable.dart';

import 'job_json.dart';

class JobScanTotals extends Equatable {
  const JobScanTotals({this.combinations = 0, this.completed = 0, this.failed = 0, this.skipped = 0, this.pending = 0, this.running = 0});

  factory JobScanTotals.fromJson(Map<String, dynamic> j) => JobScanTotals(
        combinations: jobInt(j['combinations']) ?? 0,
        completed: jobInt(j['completed']) ?? 0,
        failed: jobInt(j['failed']) ?? 0,
        skipped: jobInt(j['skipped']) ?? 0,
        pending: jobInt(j['pending']) ?? 0,
        running: jobInt(j['running']) ?? 0,
      );

  final int combinations;
  final int completed;
  final int failed;
  final int skipped;
  final int pending;
  final int running;

  int get finished => completed + failed + skipped;

  @override
  List<Object?> get props => [combinations, completed, failed, skipped, pending, running];
}

class JobScanJobs extends Equatable {
  const JobScanJobs({this.found = 0, this.newJobs = 0, this.updated = 0, this.duplicate = 0});

  factory JobScanJobs.fromJson(Map<String, dynamic> j) => JobScanJobs(
        found: jobInt(j['found']) ?? 0,
        newJobs: jobInt(j['new']) ?? 0,
        updated: jobInt(j['updated']) ?? 0,
        duplicate: jobInt(j['duplicate']) ?? 0,
      );

  final int found;
  final int newJobs;
  final int updated;
  final int duplicate;

  @override
  List<Object?> get props => [found, newJobs, updated, duplicate];
}

/// Statistics of one source within one scan.
class JobScanSource extends Equatable {
  const JobScanSource({
    required this.id,
    this.state = 'ready',
    this.requests = 0,
    this.found = 0,
    this.newJobs = 0,
    this.updated = 0,
    this.duplicate = 0,
    this.errors = 0,
    this.lastError,
  });

  factory JobScanSource.fromJson(String id, Map<String, dynamic> j) => JobScanSource(
        id: id,
        state: jobString(j['state']) ?? 'ready',
        requests: jobInt(j['requests']) ?? 0,
        found: jobInt(j['found']) ?? 0,
        newJobs: jobInt(j['new']) ?? 0,
        updated: jobInt(j['updated']) ?? 0,
        duplicate: jobInt(j['duplicate']) ?? 0,
        errors: jobInt(j['errors']) ?? 0,
        lastError: j['lastError'] is Map ? jobString(jobMap(j['lastError'])['message']) : null,
      );

  final String id;

  /// ready | not_configured | quota_exhausted | auth_failed | blocked | failing | disallowed
  final String state;
  final int requests;
  final int found;
  final int newJobs;
  final int updated;
  final int duplicate;
  final int errors;
  final String? lastError;

  bool get healthy => state == 'ready';

  String get stateLabel => switch (state) {
        'ready' => errors > 0 ? 'Working, some errors' : 'Working',
        'not_configured' => 'Not configured',
        'quota_exhausted' => 'Daily limit reached',
        'auth_failed' => 'Access refused',
        'blocked' => 'Blocked by the site',
        'disallowed' => 'Not allowed (robots)',
        'failing' => 'Switched off (failing)',
        _ => humanize(state),
      };

  @override
  List<Object?> get props => [id, state, requests, found, newJobs, updated, duplicate, errors, lastError];
}

class JobScanError extends Equatable {
  const JobScanError({required this.source, required this.kind, required this.message, this.combination, this.at});

  factory JobScanError.fromJson(Map<String, dynamic> j) => JobScanError(
        source: jobString(j['source']) ?? 'engine',
        kind: jobString(j['kind']) ?? 'error',
        message: jobString(j['message']) ?? '',
        combination: jobString(j['combination']),
        at: jobDate(j['at']),
      );

  final String source;
  final String kind;
  final String message;
  final String? combination;
  final DateTime? at;

  @override
  List<Object?> get props => [source, kind, message, combination, at];
}

/// What a scan is working on right now.
class JobScanCurrent extends Equatable {
  const JobScanCurrent({this.country, this.state, this.city, this.title, this.remote = false});

  factory JobScanCurrent.fromJson(Map<String, dynamic> j) => JobScanCurrent(
        country: jobString(j['country']),
        state: jobString(j['state']),
        city: jobString(j['city']),
        title: jobString(j['title']),
        remote: j['remote'] == true,
      );

  final String? country;
  final String? state;
  final String? city;
  final String? title;
  final bool remote;

  String get where {
    final parts = [country, state, city].whereType<String>().toList();
    final dedup = [for (var i = 0; i < parts.length; i++) if (i == 0 || parts[i] != parts[i - 1]) parts[i]];
    return remote ? '${dedup.join(' › ')} (remote)' : dedup.join(' › ');
  }

  @override
  List<Object?> get props => [country, state, city, title, remote];
}

/// A scan run — live progress while active, the record afterwards.
class JobScan extends Equatable {
  const JobScan({
    required this.id,
    required this.searchId,
    required this.searchName,
    required this.status,
    this.trigger = 'manual',
    this.totals = const JobScanTotals(),
    this.percent = 0,
    this.jobs = const JobScanJobs(),
    this.sources = const [],
    this.current = const [],
    this.recentErrors = const [],
    this.enqueuing = false,
    this.startedAt,
    this.finishedAt,
  });

  factory JobScan.fromJson(Map<String, dynamic> j) {
    final sources = jobMap(j['sources']);
    return JobScan(
      id: jobString(j['id']) ?? '',
      searchId: jobString(j['searchId']) ?? '',
      searchName: jobString(j['searchName']) ?? 'Scan',
      status: jobString(j['status']) ?? 'queued',
      trigger: jobString(j['trigger']) ?? 'manual',
      totals: JobScanTotals.fromJson(jobMap(j['totals'])),
      percent: jobDouble(j['percent']) ?? 0,
      jobs: JobScanJobs.fromJson(jobMap(j['jobs'])),
      sources: [for (final e in sources.entries) if (e.value is Map) JobScanSource.fromJson(e.key, jobMap(e.value))],
      current: [for (final c in jobMaps(j['current'])) JobScanCurrent.fromJson(c)],
      recentErrors: [for (final e in jobMaps(j['recentErrors'])) JobScanError.fromJson(e)],
      enqueuing: j['enqueuing'] == true,
      startedAt: jobDate(j['startedAt']),
      finishedAt: jobDate(j['finishedAt']),
    );
  }

  final String id;
  final String searchId;
  final String searchName;

  /// queued | running | paused | stopping | completed | stopped | failed | interrupted
  final String status;
  final String trigger;
  final JobScanTotals totals;
  final double percent;
  final JobScanJobs jobs;
  final List<JobScanSource> sources;
  final List<JobScanCurrent> current;
  final List<JobScanError> recentErrors;
  final bool enqueuing;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isActive => const {'queued', 'running', 'paused', 'stopping', 'interrupted'}.contains(status);
  bool get canPause => status == 'running';
  bool get canResume => status == 'paused' || status == 'interrupted';
  bool get canStop => isActive && status != 'stopping';
  bool get succeeded => status == 'completed';

  Duration? get elapsed => startedAt == null ? null : (finishedAt ?? DateTime.now()).difference(startedAt!);

  @override
  List<Object?> get props => [id, status, totals, percent, jobs, sources, current, recentErrors, enqueuing, finishedAt];
}

/// A combination that failed, and why.
class JobScanFailure extends Equatable {
  const JobScanFailure({required this.label, this.attempts = 0, this.message, this.kind});

  factory JobScanFailure.fromJson(Map<String, dynamic> j) {
    final parts = [jobString(j['country']), jobString(j['state']), jobString(j['city'])].whereType<String>().toList();
    final where = [for (var i = 0; i < parts.length; i++) if (i == 0 || parts[i] != parts[i - 1]) parts[i]].join(' › ');
    final err = jobMap(j['error']);
    return JobScanFailure(
      label: '$where · ${jobString(j['title']) ?? ''}',
      attempts: jobInt(j['attempts']) ?? 0,
      message: jobString(err['message']),
      kind: jobString(err['kind']),
    );
  }

  final String label;
  final int attempts;
  final String? message;
  final String? kind;

  @override
  List<Object?> get props => [label, attempts, message, kind];
}
