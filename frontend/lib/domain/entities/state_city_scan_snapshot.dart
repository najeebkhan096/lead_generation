import 'package:equatable/equatable.dart';

import 'multi_search_snapshot.dart' show ArchiveResult;

/// One city a worker has claimed and is actively scraping right now, plus
/// its most recent live status message straight from the scraper (e.g.
/// "opening listing 4/20") — without this, a claimed city just vanishes
/// from view between leaving `pending` and landing in `covered`/`failed`,
/// which is what makes a genuinely-working scan look stuck.
class CityInProgress extends Equatable {
  const CityInProgress({required this.city, this.message = ''});

  final String city;
  final String message;

  factory CityInProgress.fromJson(Map<String, dynamic> json) {
    return CityInProgress(city: (json['city'] as String?) ?? '', message: (json['message'] as String?) ?? '');
  }

  @override
  List<Object?> get props => [city, message];
}

/// One state's live progress within a category's scan — the source of
/// truth for the detailed "which cities are covered vs. still pending"
/// view. `covered`/`pending`/`failed` are city names, not just counts, so
/// the UI can list them directly.
class StateCityProgress extends Equatable {
  const StateCityProgress({
    required this.state,
    required this.status,
    required this.citiesTotal,
    this.covered = const [],
    this.pending = const [],
    this.inProgress = const [],
    this.failed = const [],
    this.leadsCollected = 0,
    this.businessesProcessed = 0,
    this.startedAt,
    this.finishedAt,
  });

  final String state;

  /// pending | running | done
  final String status;
  final int citiesTotal;
  final List<String> covered;
  final List<String> pending;
  final List<CityInProgress> inProgress;
  final List<String> failed;
  final int leadsCollected;
  final int businessesProcessed;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  int get citiesDone => covered.length + failed.length;

  factory StateCityProgress.fromJson(Map<String, dynamic> json) {
    DateTime? ms(dynamic v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return StateCityProgress(
      state: (json['state'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      citiesTotal: (json['citiesTotal'] as num?)?.toInt() ?? 0,
      covered: ((json['covered'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      pending: ((json['pending'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      inProgress: ((json['inProgress'] as List<dynamic>?) ?? const [])
          .map((e) => CityInProgress.fromJson(e as Map<String, dynamic>))
          .toList(),
      failed: ((json['failed'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      leadsCollected: (json['leadsCollected'] as num?)?.toInt() ?? 0,
      businessesProcessed: (json['businessesProcessed'] as num?)?.toInt() ?? 0,
      startedAt: ms(json['startedAt']),
      finishedAt: ms(json['finishedAt']),
    );
  }

  @override
  List<Object?> get props => [state, status, citiesTotal, covered, pending, inProgress, failed, leadsCollected];
}

/// One category's own archive lifecycle within the scan — one workbook per
/// category, one sheet per state, checkpointed after every state finishes.
class StateCityArchive extends Equatable {
  const StateCityArchive({required this.status, this.result, this.error});

  /// pending | building | partial | done | failed
  final String status;
  final ArchiveResult? result;
  final String? error;

  factory StateCityArchive.fromJson(Map<String, dynamic> json) {
    return StateCityArchive(
      status: (json['status'] as String?) ?? 'pending',
      result: json['result'] == null ? null : ArchiveResult.fromJson(json['result'] as Map<String, dynamic>),
      error: json['error'] as String?,
    );
  }

  @override
  List<Object?> get props => [status, result, error];
}

/// One category's full progress: every state, in order, plus rollup stats.
class CategoryStateProgress extends Equatable {
  const CategoryStateProgress({
    required this.category,
    required this.status,
    required this.statesTotal,
    required this.statesDone,
    required this.citiesTotal,
    required this.citiesDone,
    required this.leadsCollected,
    required this.businessesProcessed,
    required this.archive,
    this.states = const [],
  });

  final String category;

  /// pending | running | done
  final String status;
  final int statesTotal;
  final int statesDone;
  final int citiesTotal;
  final int citiesDone;
  final int leadsCollected;
  final int businessesProcessed;
  final StateCityArchive archive;
  final List<StateCityProgress> states;

  factory CategoryStateProgress.fromJson(Map<String, dynamic> json) {
    return CategoryStateProgress(
      category: (json['category'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      statesTotal: (json['statesTotal'] as num?)?.toInt() ?? 0,
      statesDone: (json['statesDone'] as num?)?.toInt() ?? 0,
      citiesTotal: (json['citiesTotal'] as num?)?.toInt() ?? 0,
      citiesDone: (json['citiesDone'] as num?)?.toInt() ?? 0,
      leadsCollected: (json['leadsCollected'] as num?)?.toInt() ?? 0,
      businessesProcessed: (json['businessesProcessed'] as num?)?.toInt() ?? 0,
      archive: StateCityArchive.fromJson((json['archive'] as Map<String, dynamic>?) ?? const {}),
      states: ((json['states'] as List<dynamic>?) ?? const [])
          .map((e) => StateCityProgress.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [category, status, statesDone, citiesDone, leadsCollected, archive];
}

class StateScanActivityEntry extends Equatable {
  const StateScanActivityEntry({required this.timestamp, required this.level, required this.message});

  final DateTime timestamp;
  final String level;
  final String message;

  factory StateScanActivityEntry.fromJson(Map<String, dynamic> json) {
    return StateScanActivityEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num?)?.toInt() ?? 0),
      level: (json['level'] as String?) ?? 'info',
      message: (json['message'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [timestamp, level, message];
}

/// Full live-dashboard snapshot polled from `/api/state-scan/status`.
class StateCityScanSnapshot extends Equatable {
  const StateCityScanSnapshot({
    required this.active,
    required this.status,
    this.concurrency,
    this.currentCategory,
    this.paused = false,
    this.startedAt,
    this.finishedAt,
    this.categories = const [],
    this.activity = const [],
  });

  final bool active;

  /// idle | running | done
  final String status;
  final int? concurrency;
  final String? currentCategory;
  final bool paused;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<CategoryStateProgress> categories;
  final List<StateScanActivityEntry> activity;

  bool get hasJob => status != 'idle';

  factory StateCityScanSnapshot.fromJson(Map<String, dynamic> json) {
    DateTime? ms(dynamic v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return StateCityScanSnapshot(
      active: json['active'] == true,
      status: (json['status'] as String?) ?? 'idle',
      concurrency: (json['concurrency'] as num?)?.toInt(),
      currentCategory: json['currentCategory'] as String?,
      paused: json['paused'] == true,
      startedAt: ms(json['startedAt']),
      finishedAt: ms(json['finishedAt']),
      categories: ((json['categories'] as List<dynamic>?) ?? const [])
          .map((e) => CategoryStateProgress.fromJson(e as Map<String, dynamic>))
          .toList(),
      activity: ((json['activity'] as List<dynamic>?) ?? const [])
          .map((e) => StateScanActivityEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [active, status, concurrency, currentCategory, paused, categories, activity];
}
