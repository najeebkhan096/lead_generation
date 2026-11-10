import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/job.dart';
import '../../../domain/entities/job_application.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../../domain/repositories/jobs_repository.dart';
import 'jobs_errors.dart';

class JobDetailsState extends Equatable {
  const JobDetailsState({this.loading = true, this.job, this.error, this.busy = false, this.message, this.messageIsError = false, this.match, this.matching = false, this.changed = false});

  final bool loading;
  final Job? job;
  final String? error;
  final bool busy;
  final String? message;
  final bool messageIsError;
  final JobMatch? match;
  final bool matching;

  /// Something about the job was changed here — the list behind should reload.
  final bool changed;

  JobDetailsState copyWith({bool? loading, Job? job, Object? error = _keep, bool? busy, Object? message = _keep, bool? messageIsError, Object? match = _keep, bool? matching, bool? changed}) => JobDetailsState(
        loading: loading ?? this.loading,
        job: job ?? this.job,
        error: identical(error, _keep) ? this.error : error as String?,
        busy: busy ?? this.busy,
        message: identical(message, _keep) ? this.message : message as String?,
        messageIsError: messageIsError ?? this.messageIsError,
        match: identical(match, _keep) ? this.match : match as JobMatch?,
        matching: matching ?? this.matching,
        changed: changed ?? this.changed,
      );

  @override
  List<Object?> get props => [loading, job, error, busy, message, messageIsError, match, matching, changed];
}

const Object _keep = Object();

/// One job in full, with the actions available on it.
class JobDetailsCubit extends Cubit<JobDetailsState> {
  JobDetailsCubit(this._repo, this.jobId) : super(const JobDetailsState());

  final JobsRepository _repo;
  final String jobId;

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: null));
    try {
      emit(state.copyWith(loading: false, job: await _repo.job(jobId)));
    } catch (e) {
      emit(state.copyWith(loading: false, error: jobsErrorMessage(e)));
    }
  }

  Future<void> _act(String done, Future<Job?> Function() action) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, message: null));
    try {
      final job = await action();
      emit(state.copyWith(busy: false, job: job, changed: true, message: done, messageIsError: false));
    } catch (e) {
      emit(state.copyWith(busy: false, message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<Job> _reload() => _repo.job(jobId);

  Future<void> setStage(ApplicationStage stage) => _act('Moved to ${stage.label}.', () async {
        await _repo.saveApplication(jobId, stage: stage);
        return _reload();
      });

  Future<void> removeFromTracker() => _act('Removed from the tracker.', () async {
        await _repo.removeApplication(jobId);
        return _reload();
      });

  Future<void> markExpired() => _act('Marked as expired.', () => _repo.setJobStatus(jobId, 'expired'));
  Future<void> markActive() => _act('Marked as active.', () => _repo.setJobStatus(jobId, 'active'));
  Future<void> saveNotes(String notes) => _act('Notes saved.', () => _repo.saveJobNotes(jobId, notes));

  /// Re-checks the posting at its sources. A source that can't be reached never expires the job.
  Future<void> verify() => _act('Checked at the sources.', () => _repo.verifyJob(jobId));

  Future<void> compareWithCv(String cvText) async {
    if (cvText.trim().isEmpty) return;
    emit(state.copyWith(matching: true, match: null, message: null));
    try {
      emit(state.copyWith(matching: false, match: await _repo.matchJob(jobId, cvText)));
    } catch (e) {
      emit(state.copyWith(matching: false, message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  void clearMessage() => emit(state.copyWith(message: null));
}
