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
    this.waValidated = 0,
    this.waChecked = 0,
    this.incompleteBusinesses = 0,
    this.skippedListings = 0,
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

  /// Of the review leads already saved live, how many were confirmed on
  /// WhatsApp — a strict subset of `leadsCollected`, not a separate pool.
  final int waValidated;

  /// How many review leads were actually looked up on WhatsApp Web
  /// (registered or not). Zero means the session wasn't connected.
  final int waChecked;

  /// Businesses whose reviews could not be proven fully read, and listings
  /// that could not be opened: what the scan may have missed in this state.
  final int incompleteBusinesses;
  final int skippedListings;
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
      waValidated: (json['waValidated'] as num?)?.toInt() ?? 0,
      waChecked: (json['waChecked'] as num?)?.toInt() ?? 0,
      incompleteBusinesses: (json['incompleteBusinesses'] as num?)?.toInt() ?? 0,
      skippedListings: (json['skippedListings'] as num?)?.toInt() ?? 0,
      startedAt: ms(json['startedAt']),
      finishedAt: ms(json['finishedAt']),
    );
  }

  @override
  List<Object?> get props => [state, status, citiesTotal, covered, pending, inProgress, failed, leadsCollected];
}

/// One category's own archive lifecycle within the scan — one workbook per
/// category, one sheet per state, checkpointed after every state finishes.
/// Google's "unusual traffic" check has the scan paused; it looks again at
/// [retryAt] and continues by itself once Google serves results.
class ScanBlockInfo extends Equatable {
  const ScanBlockInfo({required this.since, this.retryAt, this.checks = 0});

  final DateTime since;
  final DateTime? retryAt;
  final int checks;

  factory ScanBlockInfo.fromJson(Map<String, dynamic> json) {
    DateTime? ms(dynamic v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return ScanBlockInfo(
      since: ms(json['since']) ?? DateTime.now(),
      retryAt: ms(json['retryAt']),
      checks: (json['checks'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [since, retryAt, checks];
}

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
    this.waValidated = 0,
    this.waChecked = 0,
    this.incompleteBusinesses = 0,
    this.skippedListings = 0,
    this.duplicatesSkipped = 0,
    this.prefiltered = 0,
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

  /// Of `leadsCollected`, how many are already confirmed on WhatsApp.
  final int waValidated;

  /// How many of those leads were looked up on WhatsApp Web.
  final int waChecked;

  /// What the scan may have missed in this category (see [StateCityProgress]).
  final int incompleteBusinesses;
  final int skippedListings;

  /// Listings not opened: repeats of a business already read for a neighbouring
  /// place, and ones whose rating and review count prove they hold no 1-star.
  final int duplicatesSkipped;
  final int prefiltered;
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
      waValidated: (json['waValidated'] as num?)?.toInt() ?? 0,
      waChecked: (json['waChecked'] as num?)?.toInt() ?? 0,
      incompleteBusinesses: (json['incompleteBusinesses'] as num?)?.toInt() ?? 0,
      skippedListings: (json['skippedListings'] as num?)?.toInt() ?? 0,
      duplicatesSkipped: (json['duplicatesSkipped'] as num?)?.toInt() ?? 0,
      prefiltered: (json['prefiltered'] as num?)?.toInt() ?? 0,
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
    this.waValidated = 0,
    this.waChecked = 0,
    this.stoppedReason,
    this.blocked,
    this.coverage,
    this.pacePerMinute,
    this.paceMax,
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

  /// Job-wide count of review leads already confirmed on WhatsApp,
  /// summed across every category (see `saveLeadLive`).
  final int waValidated;

  /// Job-wide count of leads actually looked up on WhatsApp Web.
  final int waChecked;

  /// Why the scan stopped by itself, e.g. `google_session_expired`.
  final String? stoppedReason;

  /// Non-null while Google's check has the scan paused.
  final ScanBlockInfo? blocked;

  /// standard | extended | maximum, and the current page pace (it finds its own level).
  final String? coverage;
  final double? pacePerMinute;
  final double? paceMax;
  final List<CategoryStateProgress> categories;
  final List<StateScanActivityEntry> activity;

  bool get hasJob => status != 'idle';

  bool get stoppedForSignIn => stoppedReason == 'google_session_expired';

  /// Businesses not proven fully read plus listings not opened, whole job.
  int get skippedWithoutOpening => categories.fold(0, (n, c) => n + c.duplicatesSkipped + c.prefiltered);

  int get needsRecheck => categories.fold(0, (n, c) => n + c.incompleteBusinesses + c.skippedListings);

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
      waValidated: (json['waValidated'] as num?)?.toInt() ?? 0,
      waChecked: (json['waChecked'] as num?)?.toInt() ?? 0,
      stoppedReason: json['stoppedReason'] as String?,
      blocked: json['blocked'] is Map<String, dynamic> ? ScanBlockInfo.fromJson(json['blocked'] as Map<String, dynamic>) : null,
      coverage: json['coverage'] as String?,
      pacePerMinute: ((json['pace'] as Map<String, dynamic>?)?['perMinute'] as num?)?.toDouble(),
      paceMax: ((json['pace'] as Map<String, dynamic>?)?['max'] as num?)?.toDouble(),
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
