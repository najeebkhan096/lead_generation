import 'package:equatable/equatable.dart';

import '../../../../domain/entities/job_scan.dart';
import '../../../../domain/entities/paged.dart';

class JobsScanState extends Equatable {
  const JobsScanState({
    this.loading = true,
    this.active = const [],
    this.history = const Paged(items: []),
    this.loadingMoreHistory = false,
    this.selectedId,
    this.failures = const [],
    this.busy = const {},
    this.starting = false,
    this.message,
    this.messageIsError = true,
    this.finishedTick = 0,
  });

  final bool loading;

  /// Scans that are queued, running, paused or stopping — with live numbers.
  final List<JobScan> active;
  final Paged<JobScan> history;
  final bool loadingMoreHistory;

  /// The scan whose detail (per-source numbers, errors) is open.
  final String? selectedId;
  final List<JobScanFailure> failures;

  /// Scans with a control request in flight.
  final Set<String> busy;
  final bool starting;
  final String? message;
  final bool messageIsError;

  /// Bumped each time a scan leaves the active set — other tabs refresh on it.
  final int finishedTick;

  JobScan? get selected {
    if (selectedId == null) return null;
    for (final s in active) {
      if (s.id == selectedId) return s;
    }
    for (final s in history.items) {
      if (s.id == selectedId) return s;
    }
    return null;
  }

  /// The scan to feature: the selected one, else the first running.
  JobScan? get featured => selected ?? (active.isEmpty ? null : active.first);

  bool get anyActive => active.isNotEmpty;

  JobsScanState copyWith({
    bool? loading,
    List<JobScan>? active,
    Paged<JobScan>? history,
    bool? loadingMoreHistory,
    Object? selectedId = _keep,
    List<JobScanFailure>? failures,
    Set<String>? busy,
    bool? starting,
    Object? message = _keep,
    bool? messageIsError,
    int? finishedTick,
  }) =>
      JobsScanState(
        loading: loading ?? this.loading,
        active: active ?? this.active,
        history: history ?? this.history,
        loadingMoreHistory: loadingMoreHistory ?? this.loadingMoreHistory,
        selectedId: identical(selectedId, _keep) ? this.selectedId : selectedId as String?,
        failures: failures ?? this.failures,
        busy: busy ?? this.busy,
        starting: starting ?? this.starting,
        message: identical(message, _keep) ? this.message : message as String?,
        messageIsError: messageIsError ?? this.messageIsError,
        finishedTick: finishedTick ?? this.finishedTick,
      );

  @override
  List<Object?> get props => [loading, active, history, loadingMoreHistory, selectedId, failures, busy, starting, message, messageIsError, finishedTick];
}

const Object _keep = Object();
