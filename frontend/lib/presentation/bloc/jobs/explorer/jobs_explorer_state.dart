import 'package:equatable/equatable.dart';

import '../../../../domain/entities/job.dart';
import '../../../../domain/entities/job_filters.dart';

enum JobsExplorerStatus { initial, loading, success, failure }

class JobsExplorerState extends Equatable {
  const JobsExplorerState({
    this.status = JobsExplorerStatus.initial,
    this.filters = const JobFilters(),
    this.jobs = const [],
    this.nextCursor,
    this.total,
    this.loadingMore = false,
    this.error,
    this.selected = const {},
    this.busy = const {},
    this.message,
    this.messageIsError = false,
  });

  final JobsExplorerStatus status;
  final JobFilters filters;

  /// Only the pages loaded so far — never the whole collection.
  final List<Job> jobs;
  final String? nextCursor;

  /// Matching jobs, when the server can say (the indexed path's first page).
  final int? total;
  final bool loadingMore;
  final String? error;
  final Set<String> selected;
  final Set<String> busy;
  final String? message;
  final bool messageIsError;

  bool get hasMore => nextCursor != null;
  bool get loading => status == JobsExplorerStatus.loading;
  bool get hasSelection => selected.isNotEmpty;
  bool get allLoadedSelected => jobs.isNotEmpty && jobs.every((j) => selected.contains(j.id));

  JobsExplorerState copyWith({
    JobsExplorerStatus? status,
    JobFilters? filters,
    List<Job>? jobs,
    Object? nextCursor = _keep,
    Object? total = _keep,
    bool? loadingMore,
    Object? error = _keep,
    Set<String>? selected,
    Set<String>? busy,
    Object? message = _keep,
    bool? messageIsError,
  }) =>
      JobsExplorerState(
        status: status ?? this.status,
        filters: filters ?? this.filters,
        jobs: jobs ?? this.jobs,
        nextCursor: identical(nextCursor, _keep) ? this.nextCursor : nextCursor as String?,
        total: identical(total, _keep) ? this.total : total as int?,
        loadingMore: loadingMore ?? this.loadingMore,
        error: identical(error, _keep) ? this.error : error as String?,
        selected: selected ?? this.selected,
        busy: busy ?? this.busy,
        message: identical(message, _keep) ? this.message : message as String?,
        messageIsError: messageIsError ?? this.messageIsError,
      );

  @override
  List<Object?> get props => [status, filters, jobs, nextCursor, total, loadingMore, error, selected, busy, message, messageIsError];
}

const Object _keep = Object();
