import 'package:equatable/equatable.dart';

enum CategoryScanStatus {
  queued,
  starting,
  searching,
  scraping,
  saving,
  completed,
  failed,
  cancelled;

  static CategoryScanStatus fromJson(String? value) {
    return CategoryScanStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CategoryScanStatus.queued,
    );
  }

  bool get isRunning =>
      this == starting || this == searching || this == scraping || this == saving;

  bool get isTerminal => this == completed || this == failed || this == cancelled;
}

class ActivityLogEntry extends Equatable {
  const ActivityLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final String level; // info | warn | error
  final String message;

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ActivityLogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num?)?.toInt() ?? 0),
      level: (json['level'] as String?) ?? 'info',
      message: (json['message'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [timestamp, level, message];
}

class CategoryWarning extends Equatable {
  const CategoryWarning({required this.timestamp, required this.message});

  final DateTime timestamp;
  final String message;

  factory CategoryWarning.fromJson(Map<String, dynamic> json) {
    return CategoryWarning(
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num?)?.toInt() ?? 0),
      message: (json['message'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [timestamp, message];
}

class CategoryProgress extends Equatable {
  const CategoryProgress({
    required this.category,
    required this.status,
    this.workerId,
    required this.progressPercent,
    this.currentState,
    required this.statesDone,
    required this.statesTotal,
    required this.statesRemaining,
    required this.businessesProcessed,
    required this.leadsCollected,
    this.startedAt,
    required this.elapsedMs,
    this.etaMs,
    this.lastActivityAt,
    this.warnings = const [],
    this.error,
    this.paused = false,
  });

  final String category;
  final CategoryScanStatus status;
  final int? workerId;
  final int progressPercent;
  final String? currentState;
  final int statesDone;
  final int statesTotal;
  final int statesRemaining;
  final int businessesProcessed;
  final int leadsCollected;
  final DateTime? startedAt;
  final int elapsedMs;
  final int? etaMs;
  final DateTime? lastActivityAt;
  final List<CategoryWarning> warnings;
  final String? error;
  final bool paused;

  factory CategoryProgress.fromJson(Map<String, dynamic> json) {
    DateTime? ms(dynamic v) =>
        v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

    return CategoryProgress(
      category: (json['category'] as String?) ?? '',
      status: CategoryScanStatus.fromJson(json['status'] as String?),
      workerId: (json['workerId'] as num?)?.toInt(),
      progressPercent: (json['progressPercent'] as num?)?.toInt() ?? 0,
      currentState: json['currentState'] as String?,
      statesDone: (json['statesDone'] as num?)?.toInt() ?? 0,
      statesTotal: (json['statesTotal'] as num?)?.toInt() ?? 0,
      statesRemaining: (json['statesRemaining'] as num?)?.toInt() ?? 0,
      businessesProcessed: (json['businessesProcessed'] as num?)?.toInt() ?? 0,
      leadsCollected: (json['leadsCollected'] as num?)?.toInt() ?? 0,
      startedAt: ms(json['startedAt']),
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      etaMs: (json['etaMs'] as num?)?.toInt(),
      lastActivityAt: ms(json['lastActivityAt']),
      warnings: ((json['warnings'] as List<dynamic>?) ?? const [])
          .map((w) => CategoryWarning.fromJson(w as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
      paused: json['paused'] == true,
    );
  }

  @override
  List<Object?> get props => [
        category,
        status,
        workerId,
        progressPercent,
        currentState,
        statesDone,
        statesTotal,
        leadsCollected,
        error,
        paused,
      ];
}

class OverallProgress extends Equatable {
  const OverallProgress({
    required this.percent,
    required this.totalCategories,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.running,
    required this.queued,
    required this.totalStatesDone,
    required this.totalStatesRemaining,
    required this.totalLeads,
    required this.elapsedMs,
    this.etaMs,
    required this.activeWorkers,
    this.paused = false,
  });

  final int percent;
  final int totalCategories;
  final int completed;
  final int failed;
  final int cancelled;
  final int running;
  final int queued;
  final int totalStatesDone;
  final int totalStatesRemaining;
  final int totalLeads;
  final int elapsedMs;
  final int? etaMs;
  final int activeWorkers;
  final bool paused;

  factory OverallProgress.fromJson(Map<String, dynamic> json) {
    return OverallProgress(
      percent: (json['percent'] as num?)?.toInt() ?? 0,
      totalCategories: (json['totalCategories'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      running: (json['running'] as num?)?.toInt() ?? 0,
      queued: (json['queued'] as num?)?.toInt() ?? 0,
      totalStatesDone: (json['totalStatesDone'] as num?)?.toInt() ?? 0,
      totalStatesRemaining: (json['totalStatesRemaining'] as num?)?.toInt() ?? 0,
      totalLeads: (json['totalLeads'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      etaMs: (json['etaMs'] as num?)?.toInt(),
      activeWorkers: (json['activeWorkers'] as num?)?.toInt() ?? 0,
      paused: json['paused'] == true,
    );
  }

  @override
  List<Object?> get props => [
        percent,
        totalCategories,
        completed,
        failed,
        cancelled,
        running,
        queued,
        totalStatesDone,
        totalLeads,
        activeWorkers,
      ];
}

class MultiSearchFinalStats extends Equatable {
  const MultiSearchFinalStats({
    required this.totalExecutionMs,
    required this.totalLeads,
    required this.leadsPerCategory,
    required this.statesProcessed,
    required this.successCount,
    required this.failureCount,
    required this.cancelledCount,
    this.avgMsPerState,
    this.avgMsPerCategory,
  });

  final int totalExecutionMs;
  final int totalLeads;
  final Map<String, int> leadsPerCategory;
  final int statesProcessed;
  final int successCount;
  final int failureCount;
  final int cancelledCount;
  final double? avgMsPerState;
  final double? avgMsPerCategory;

  factory MultiSearchFinalStats.fromJson(Map<String, dynamic> json) {
    final perCategory = (json['leadsPerCategory'] as Map<String, dynamic>?) ?? const {};
    return MultiSearchFinalStats(
      totalExecutionMs: (json['totalExecutionMs'] as num?)?.toInt() ?? 0,
      totalLeads: (json['totalLeads'] as num?)?.toInt() ?? 0,
      leadsPerCategory: perCategory.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      statesProcessed: (json['statesProcessed'] as num?)?.toInt() ?? 0,
      successCount: (json['successCount'] as num?)?.toInt() ?? 0,
      failureCount: (json['failureCount'] as num?)?.toInt() ?? 0,
      cancelledCount: (json['cancelledCount'] as num?)?.toInt() ?? 0,
      avgMsPerState: (json['avgMsPerState'] as num?)?.toDouble(),
      avgMsPerCategory: (json['avgMsPerCategory'] as num?)?.toDouble(),
    );
  }

  @override
  List<Object?> get props => [totalExecutionMs, totalLeads, statesProcessed, successCount, failureCount, cancelledCount];
}

/// Full live-dashboard snapshot polled from `/api/search/multi/status`.
class MultiSearchSnapshot extends Equatable {
  const MultiSearchSnapshot({
    required this.active,
    required this.status,
    this.concurrency,
    this.overall,
    this.categories = const [],
    this.activity = const [],
    this.finalStats,
  });

  final bool active;
  final String status; // idle | running | done
  final int? concurrency;
  final OverallProgress? overall;
  final List<CategoryProgress> categories;
  final List<ActivityLogEntry> activity;
  final MultiSearchFinalStats? finalStats;

  bool get hasJob => status != 'idle';

  factory MultiSearchSnapshot.fromJson(Map<String, dynamic> json) {
    return MultiSearchSnapshot(
      active: json['active'] == true,
      status: (json['status'] as String?) ?? 'idle',
      concurrency: (json['concurrency'] as num?)?.toInt(),
      overall: json['overall'] == null
          ? null
          : OverallProgress.fromJson(json['overall'] as Map<String, dynamic>),
      categories: ((json['categories'] as List<dynamic>?) ?? const [])
          .map((c) => CategoryProgress.fromJson(c as Map<String, dynamic>))
          .toList(),
      activity: ((json['activity'] as List<dynamic>?) ?? const [])
          .map((a) => ActivityLogEntry.fromJson(a as Map<String, dynamic>))
          .toList(),
      finalStats: json['finalStats'] == null
          ? null
          : MultiSearchFinalStats.fromJson(json['finalStats'] as Map<String, dynamic>),
    );
  }

  @override
  List<Object?> get props => [active, status, concurrency, overall, categories, activity, finalStats];
}
