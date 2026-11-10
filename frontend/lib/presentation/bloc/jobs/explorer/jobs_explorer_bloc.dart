import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/job.dart';
import '../../../../domain/entities/job_application.dart';
import '../../../../domain/entities/job_filters.dart';
import '../../../../domain/repositories/jobs_repository.dart';
import '../jobs_errors.dart';
import 'jobs_explorer_event.dart';
import 'jobs_explorer_state.dart';

/// Pages through discovered jobs. Filtering, sorting and paging are the
/// server's job: the bloc holds only the pages it has loaded and asks for the
/// next one when the list is scrolled near its end.
class JobsExplorerBloc extends Bloc<JobsExplorerEvent, JobsExplorerState> {
  JobsExplorerBloc(this._repo, {this.pageSize = 25, this.searchDebounce = const Duration(milliseconds: 400)}) : super(const JobsExplorerState()) {
    on<JobsExplorerStarted>((e, emit) => _reload(emit));
    on<JobsExplorerRefreshed>((e, emit) => _reload(emit, keepList: true));
    on<JobsExplorerFiltersChanged>((e, emit) => _reload(emit, seed: state.copyWith(filters: e.filters, selected: const {})));
    on<JobsExplorerQueryChanged>(_onQuery);
    on<JobsExplorerLoadMore>(_onLoadMore);
    on<JobsExplorerToggled>(_onToggled);
    on<JobsExplorerSelectLoaded>((e, emit) => emit(state.copyWith(selected: {...state.selected, ...state.jobs.map((j) => j.id)})));
    on<JobsExplorerSelectionCleared>((e, emit) => emit(state.copyWith(selected: const {})));
    on<JobsExplorerTriaged>(_onTriaged);
    on<JobsExplorerMessageCleared>((e, emit) => emit(state.copyWith(message: null)));
  }

  final JobsRepository _repo;
  final int pageSize;
  final Duration searchDebounce;
  Timer? _debounce;

  /// Bumped on every reload so a response to a superseded request is dropped.
  int _generation = 0;

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }

  Future<void> _reload(Emitter<JobsExplorerState> emit, {JobsExplorerState? seed, bool keepList = false}) async {
    final generation = ++_generation;
    var loading = (seed ?? state).copyWith(status: JobsExplorerStatus.loading, loadingMore: false, error: null);
    // A refresh keeps the list on screen while it reloads; a filter change clears it.
    if (!keepList) loading = loading.copyWith(jobs: const [], nextCursor: null, total: null);
    emit(loading);
    try {
      final page = await _repo.jobs(state.filters, limit: pageSize);
      if (generation != _generation) return;
      final present = page.items.map((j) => j.id).toSet();
      emit(state.copyWith(
        status: JobsExplorerStatus.success,
        jobs: page.items,
        nextCursor: page.nextCursor,
        total: page.total,
        selected: state.selected.where(present.contains).toSet(),
      ));
    } catch (e) {
      if (generation != _generation) return;
      emit(state.copyWith(status: JobsExplorerStatus.failure, error: jobsErrorMessage(e)));
    }
  }

  void _onQuery(JobsExplorerQueryChanged event, Emitter<JobsExplorerState> emit) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () {
      if (isClosed) return;
      final q = event.query.trim();
      add(JobsExplorerFiltersChanged(state.filters.copyWith(query: q.isEmpty ? null : q)));
    });
  }

  Future<void> _onLoadMore(JobsExplorerLoadMore event, Emitter<JobsExplorerState> emit) async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    final generation = _generation;
    emit(state.copyWith(loadingMore: true));
    try {
      final page = await _repo.jobs(state.filters, cursor: state.nextCursor, limit: pageSize);
      if (generation != _generation) return;
      final known = state.jobs.map((j) => j.id).toSet();
      emit(state.copyWith(
        jobs: [...state.jobs, ...page.items.where((j) => !known.contains(j.id))],
        nextCursor: page.nextCursor,
        loadingMore: false,
      ));
      // A server-side scan may return a short page with a cursor; ask again so a sparse
      // filter doesn't leave the list looking finished while more matches exist.
      if (page.items.isEmpty && page.nextCursor != null) add(const JobsExplorerLoadMore());
    } catch (e) {
      if (generation != _generation) return;
      emit(state.copyWith(loadingMore: false, message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  void _onToggled(JobsExplorerToggled event, Emitter<JobsExplorerState> emit) {
    final next = {...state.selected};
    if (!next.remove(event.id)) next.add(event.id);
    emit(state.copyWith(selected: next));
  }

  Future<void> _onTriaged(JobsExplorerTriaged event, Emitter<JobsExplorerState> emit) async {
    final id = event.id;
    if (state.busy.contains(id)) return;
    emit(state.copyWith(busy: {...state.busy, id}, message: null));
    try {
      Job? updated;
      switch (event.action) {
        case JobTriage.save:
          await _repo.saveApplication(id, stage: ApplicationStage.saved);
          updated = _find(id)?.copyWith(userState: 'saved', applicationStage: 'saved');
        case JobTriage.applied:
          await _repo.saveApplication(id, stage: ApplicationStage.applied);
          updated = _find(id)?.copyWith(userState: 'applied', applicationStage: 'applied');
        case JobTriage.rejected:
          await _repo.saveApplication(id, stage: ApplicationStage.rejected);
          updated = _find(id)?.copyWith(userState: 'rejected', applicationStage: 'rejected');
        case JobTriage.reset:
          await _repo.removeApplication(id);
          updated = _find(id)?.copyWith(userState: 'new', clearStage: true);
        case JobTriage.expired:
          await _repo.setJobStatus(id, 'expired');
          updated = _find(id)?.copyWith(status: 'expired');
        case JobTriage.reactivate:
          await _repo.setJobStatus(id, 'active');
          updated = _find(id)?.copyWith(status: 'active');
        case JobTriage.delete:
          await _repo.deleteJob(id);
      }
      final jobs = [
        for (final j in state.jobs)
          if (j.id != id)
            j
          else if (updated != null && _belongs(updated))
            updated,
      ];
      emit(state.copyWith(
        jobs: jobs,
        total: state.total == null ? null : state.total! - (jobs.length < state.jobs.length ? 1 : 0),
        busy: {...state.busy}..remove(id),
        selected: jobs.any((j) => j.id == id) ? state.selected : ({...state.selected}..remove(id)),
        message: event.action.done,
        messageIsError: false,
      ));
    } catch (e) {
      emit(state.copyWith(busy: {...state.busy}..remove(id), message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Job? _find(String id) {
    for (final j in state.jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// Does [job] still belong in the current quick view after being changed?
  bool _belongs(Job job) => switch (state.filters.view) {
        JobView.all => true,
        JobView.active => job.status == 'active',
        JobView.newJobs => job.userState == 'new' && job.status == 'active',
        JobView.saved => job.userState == 'saved',
        JobView.applied => job.userState == 'applied',
        JobView.rejected => job.userState == 'rejected',
        JobView.expired => job.status != 'active',
      };
}
