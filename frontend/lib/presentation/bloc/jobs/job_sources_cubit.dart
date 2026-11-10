import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/job_source_info.dart';
import '../../../domain/repositories/jobs_repository.dart';
import 'jobs_errors.dart';

class JobSourcesState extends Equatable {
  const JobSourcesState({this.loading = true, this.sources = const [], this.busy = const {}, this.error, this.message, this.messageIsError = false});

  final bool loading;
  final List<JobSourceInfo> sources;
  final Set<String> busy;
  final String? error;
  final String? message;
  final bool messageIsError;

  JobSourcesState copyWith({bool? loading, List<JobSourceInfo>? sources, Set<String>? busy, Object? error = _keep, Object? message = _keep, bool? messageIsError}) => JobSourcesState(
        loading: loading ?? this.loading,
        sources: sources ?? this.sources,
        busy: busy ?? this.busy,
        error: identical(error, _keep) ? this.error : error as String?,
        message: identical(message, _keep) ? this.message : message as String?,
        messageIsError: messageIsError ?? this.messageIsError,
      );

  @override
  List<Object?> get props => [loading, sources, busy, error, message, messageIsError];
}

const Object _keep = Object();

/// Job sources: what each needs, how it is doing, and its limits and boards.
class JobSourcesCubit extends Cubit<JobSourcesState> {
  JobSourcesCubit(this._repo) : super(const JobSourcesState());

  final JobsRepository _repo;

  Future<void> load() async {
    emit(state.copyWith(loading: state.sources.isEmpty, error: null));
    try {
      emit(state.copyWith(loading: false, sources: await _repo.sources()));
    } catch (e) {
      emit(state.copyWith(loading: false, error: jobsErrorMessage(e)));
    }
  }

  Future<void> _update(String id, Future<JobSourceInfo> Function() call, String done) async {
    emit(state.copyWith(busy: {...state.busy, id}, message: null));
    try {
      final updated = await call();
      emit(state.copyWith(sources: [for (final s in state.sources) s.id == id ? updated : s], busy: {...state.busy}..remove(id), message: done, messageIsError: false));
    } catch (e) {
      emit(state.copyWith(busy: {...state.busy}..remove(id), message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> setEnabled(String id, bool enabled) => _update(id, () => _repo.updateSource(id, enabled: enabled), enabled ? 'Source enabled.' : 'Source disabled.');

  Future<void> setLimits(String id, JobSourceLimits limits) => _update(id, () => _repo.updateSource(id, limits: limits), 'Limits saved.');

  Future<void> setBoards(String id, List<String> boards) => _update(id, () => _repo.updateSource(id, boards: boards), 'Boards saved.');

  Future<void> setCareerPages(String id, List<JobCareerPage> pages) => _update(id, () => _repo.updateSource(id, careerPages: pages), 'Career pages saved.');

  void clearMessage() => emit(state.copyWith(message: null));
}
