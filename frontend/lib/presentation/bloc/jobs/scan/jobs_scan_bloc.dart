import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/job_scan.dart';
import '../../../../domain/entities/paged.dart';
import '../../../../domain/repositories/jobs_repository.dart';
import '../jobs_errors.dart';
import 'jobs_scan_event.dart';
import 'jobs_scan_state.dart';

/// Starts, controls and follows scans. A scan runs on the server regardless of
/// this screen; the bloc only polls it (fast while something is running, slowly
/// otherwise) and sends pause / resume / stop.
class JobsScanBloc extends Bloc<JobsScanEvent, JobsScanState> {
  JobsScanBloc(this._repo, {this.fastPoll = const Duration(seconds: 2), this.slowPoll = const Duration(seconds: 12)}) : super(const JobsScanState()) {
    on<JobsScanStarted>(_onStarted);
    on<JobsScanRefreshed>(_onRefreshed);
    on<JobsScanBegin>(_onBegin);
    on<JobsScanPause>((e, emit) => _control(e.runId, _repo.pauseScan, emit));
    on<JobsScanResume>((e, emit) => _control(e.runId, _repo.resumeScan, emit));
    on<JobsScanStop>((e, emit) => _control(e.runId, _repo.stopScan, emit));
    on<JobsScanSelected>(_onSelected);
    on<JobsScanMoreHistory>(_onMoreHistory);
    on<JobsScanMessageCleared>((e, emit) => emit(state.copyWith(message: null)));
  }

  final JobsRepository _repo;
  final Duration fastPoll;
  final Duration slowPoll;
  Timer? _timer;

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }

  void _schedule() {
    _timer?.cancel();
    if (isClosed) return;
    _timer = Timer(state.anyActive ? fastPoll : slowPoll, () {
      if (!isClosed) add(const JobsScanRefreshed());
    });
  }

  Future<void> _onStarted(JobsScanStarted event, Emitter<JobsScanState> emit) async {
    emit(state.copyWith(loading: true));
    await _refresh(emit, history: true);
    emit(state.copyWith(loading: false));
    _schedule();
  }

  bool _refreshing = false;

  Future<void> _onRefreshed(JobsScanRefreshed event, Emitter<JobsScanState> emit) async {
    // A slow response must not stack up further polls behind it.
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _refresh(emit, history: event.force);
    } finally {
      _refreshing = false;
    }
    _schedule();
  }

  /// Reads the running scans; when one has just finished, reads the history too
  /// and announces both together, so whoever reacts to "finished" sees current data.
  Future<void> _refresh(Emitter<JobsScanState> emit, {required bool history}) async {
    try {
      final active = await _repo.activeScans();
      final nowIds = active.map((s) => s.id).toSet();
      final finished = state.active.map((s) => s.id).toSet().difference(nowIds);
      final page = (history || finished.isNotEmpty) ? await _repo.scanHistory() : null;
      emit(state.copyWith(
        active: active,
        history: page,
        finishedTick: finished.isNotEmpty ? state.finishedTick + 1 : null,
      ));
      final open = state.selectedId;
      if (open != null && !nowIds.contains(open) && state.selected == null) {
        emit(state.copyWith(selectedId: null));
      }
    } catch (e) {
      // Polling failures are quiet unless nothing has ever loaded.
      if (state.loading) emit(state.copyWith(message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> _onBegin(JobsScanBegin event, Emitter<JobsScanState> emit) async {
    emit(state.copyWith(starting: true, message: null));
    try {
      final run = await _repo.startScan(event.searchId);
      emit(state.copyWith(
        starting: false,
        active: [run, ...state.active.where((s) => s.id != run.id)],
        selectedId: run.id,
        message: 'Scan started: ${run.totals.combinations} searches queued.',
        messageIsError: false,
      ));
      _schedule();
    } catch (e) {
      emit(state.copyWith(starting: false, message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> _control(String runId, Future<JobScan> Function(String) call, Emitter<JobsScanState> emit) async {
    if (state.busy.contains(runId)) return;
    emit(state.copyWith(busy: {...state.busy, runId}, message: null));
    try {
      final updated = await call(runId);
      emit(state.copyWith(
        busy: {...state.busy}..remove(runId),
        active: [for (final s in state.active) s.id == runId ? updated : s],
      ));
      add(const JobsScanRefreshed(force: true));
    } catch (e) {
      emit(state.copyWith(busy: {...state.busy}..remove(runId), message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> _onSelected(JobsScanSelected event, Emitter<JobsScanState> emit) async {
    emit(state.copyWith(selectedId: event.runId, failures: const []));
    final id = event.runId;
    if (id == null) return;
    try {
      final failures = await _repo.scanFailures(id);
      if (state.selectedId == id) emit(state.copyWith(failures: failures));
    } catch (_) {/* the detail still shows without the failure list */}
  }

  Future<void> _onMoreHistory(JobsScanMoreHistory event, Emitter<JobsScanState> emit) async {
    final cursor = state.history.nextCursor;
    if (cursor == null || state.loadingMoreHistory) return;
    emit(state.copyWith(loadingMoreHistory: true));
    try {
      final Paged<JobScan> more = await _repo.scanHistory(cursor: cursor);
      emit(state.copyWith(history: state.history.append(more), loadingMoreHistory: false));
    } catch (e) {
      emit(state.copyWith(loadingMoreHistory: false, message: jobsErrorMessage(e), messageIsError: true));
    }
  }
}
