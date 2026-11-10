import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/job_application.dart';
import '../../../domain/entities/paged.dart';
import '../../../domain/repositories/jobs_repository.dart';
import 'jobs_errors.dart';

class JobTrackerState extends Equatable {
  const JobTrackerState({this.loading = true, this.columns = const {}, this.counts = const {}, this.loadingMore = const {}, this.error, this.message, this.messageIsError = false});

  final bool loading;

  /// The loaded applications of each stage (a page at a time).
  final Map<ApplicationStage, Paged<JobApplication>> columns;

  /// How many applications each stage holds in all.
  final Map<ApplicationStage, int> counts;
  final Set<ApplicationStage> loadingMore;
  final String? error;
  final String? message;
  final bool messageIsError;

  int get total => counts.values.fold(0, (a, b) => a + b);

  JobTrackerState copyWith({
    bool? loading,
    Map<ApplicationStage, Paged<JobApplication>>? columns,
    Map<ApplicationStage, int>? counts,
    Set<ApplicationStage>? loadingMore,
    Object? error = _keep,
    Object? message = _keep,
    bool? messageIsError,
  }) =>
      JobTrackerState(
        loading: loading ?? this.loading,
        columns: columns ?? this.columns,
        counts: counts ?? this.counts,
        loadingMore: loadingMore ?? this.loadingMore,
        error: identical(error, _keep) ? this.error : error as String?,
        message: identical(message, _keep) ? this.message : message as String?,
        messageIsError: messageIsError ?? this.messageIsError,
      );

  @override
  List<Object?> get props => [loading, columns, counts, loadingMore, error, message, messageIsError];
}

const Object _keep = Object();

/// The application pipeline: Saved → Applied → Assessment → Interview → Offered,
/// or Rejected / Withdrawn. Each stage loads its own pages.
class JobTrackerCubit extends Cubit<JobTrackerState> {
  JobTrackerCubit(this._repo) : super(const JobTrackerState());

  final JobsRepository _repo;

  Future<void> load() async {
    emit(state.copyWith(loading: state.columns.isEmpty, error: null));
    try {
      final counts = await _repo.applicationSummary();
      final pages = await Future.wait([for (final s in ApplicationStage.values) _repo.applications(stage: s, limit: 20)]);
      emit(state.copyWith(
        loading: false,
        counts: counts,
        columns: {for (var i = 0; i < pages.length; i++) ApplicationStage.values[i]: pages[i]},
      ));
    } catch (e) {
      emit(state.copyWith(loading: false, error: jobsErrorMessage(e)));
    }
  }

  Future<void> loadMore(ApplicationStage stage) async {
    final column = state.columns[stage];
    if (column == null || !column.hasMore || state.loadingMore.contains(stage)) return;
    emit(state.copyWith(loadingMore: {...state.loadingMore, stage}));
    try {
      final more = await _repo.applications(stage: stage, cursor: column.nextCursor, limit: 20);
      emit(state.copyWith(columns: {...state.columns, stage: column.append(more)}, loadingMore: {...state.loadingMore}..remove(stage)));
    } catch (e) {
      emit(state.copyWith(loadingMore: {...state.loadingMore}..remove(stage), message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  /// Moves an application to [stage] (optimistically, then confirmed by the server).
  Future<void> move(JobApplication app, ApplicationStage stage) async {
    if (app.stage == stage) return;
    final before = state;
    final moved = app.copyWith(stage: stage);
    emit(state.copyWith(
      columns: {
        ...state.columns,
        app.stage: Paged(items: state.columns[app.stage]!.items.where((a) => a.jobId != app.jobId).toList(), nextCursor: state.columns[app.stage]!.nextCursor, total: state.columns[app.stage]!.total),
        stage: Paged(items: [moved, ...?state.columns[stage]?.items], nextCursor: state.columns[stage]?.nextCursor, total: state.columns[stage]?.total),
      },
      counts: {...state.counts, app.stage: (state.counts[app.stage] ?? 1) - 1, stage: (state.counts[stage] ?? 0) + 1},
      message: null,
    ));
    try {
      await _repo.saveApplication(app.jobId, stage: stage);
      emit(state.copyWith(message: 'Moved to ${stage.label}.', messageIsError: false));
    } catch (e) {
      emit(before.copyWith(message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> saveNotes(JobApplication app, String notes) async {
    try {
      final saved = await _repo.saveApplication(app.jobId, notes: notes);
      final column = state.columns[app.stage];
      if (column != null) {
        emit(state.copyWith(
          columns: {...state.columns, app.stage: Paged(items: [for (final a in column.items) a.jobId == app.jobId ? saved : a], nextCursor: column.nextCursor, total: column.total)},
          message: 'Notes saved.',
          messageIsError: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> remove(JobApplication app) async {
    try {
      await _repo.removeApplication(app.jobId);
      await load();
    } catch (e) {
      emit(state.copyWith(message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  void clearMessage() => emit(state.copyWith(message: null));
}
