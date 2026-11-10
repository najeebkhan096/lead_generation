import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/job_scan.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../../domain/entities/job_stats.dart';
import '../../../domain/repositories/jobs_repository.dart';
import 'jobs_errors.dart';

class JobsOverviewState extends Equatable {
  const JobsOverviewState({this.loading = true, this.stats, this.alerts = const [], this.error});

  final bool loading;
  final JobStats? stats;
  final List<JobAlert> alerts;
  final String? error;

  JobsOverviewState copyWith({bool? loading, JobStats? stats, List<JobAlert>? alerts, Object? error = _keep}) => JobsOverviewState(
        loading: loading ?? this.loading,
        stats: stats ?? this.stats,
        alerts: alerts ?? this.alerts,
        error: identical(error, _keep) ? this.error : error as String?,
      );

  @override
  List<Object?> get props => [loading, stats, alerts, error];
}

const Object _keep = Object();

/// The numbers on the Jobs overview. Refreshes itself while shown, and on
/// demand when a scan finishes.
class JobsOverviewCubit extends Cubit<JobsOverviewState> {
  JobsOverviewCubit(this._repo, {this.refreshEvery = const Duration(seconds: 30)}) : super(const JobsOverviewState());

  final JobsRepository _repo;
  final Duration refreshEvery;
  Timer? _timer;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }

  Future<void> load({bool refresh = false}) async {
    if (state.stats == null) emit(state.copyWith(loading: true, error: null));
    try {
      final results = await Future.wait<Object>([_repo.stats(refresh: refresh), _repo.alerts().then((p) => p.items)]);
      emit(JobsOverviewState(loading: false, stats: results[0] as JobStats, alerts: results[1] as List<JobAlert>));
    } catch (e) {
      emit(state.copyWith(loading: false, error: jobsErrorMessage(e)));
    }
    _timer?.cancel();
    if (!isClosed) _timer = Timer(refreshEvery, () => load());
  }

  /// The last scan's live numbers are shown by the scan bloc; this keeps the
  /// failure statistics current after one finishes.
  Future<void> scanFinished() => load(refresh: true);

  Future<void> deleteAlert(String id) async {
    try {
      await _repo.deleteAlert(id);
      emit(state.copyWith(alerts: state.alerts.where((a) => a.id != id).toList()));
    } catch (e) {
      emit(state.copyWith(error: jobsErrorMessage(e)));
    }
  }

  Future<void> createAlert(String name, Map<String, dynamic> filters) async {
    try {
      final alert = await _repo.createAlert(name, filters);
      emit(state.copyWith(alerts: [alert, ...state.alerts]));
    } catch (e) {
      emit(state.copyWith(error: jobsErrorMessage(e)));
    }
  }
}

/// A stat-only view of the last scan's finish state for the overview's "last scan" card.
extension JobScanSummary on JobScan {
  String get statusLabel => switch (status) {
        'completed' => 'Completed',
        'stopped' => 'Stopped',
        'failed' => 'Failed',
        'running' => 'Running',
        'paused' => 'Paused',
        'stopping' => 'Stopping',
        'interrupted' => 'Interrupted — will resume',
        'queued' => 'Starting',
        _ => status,
      };
}
