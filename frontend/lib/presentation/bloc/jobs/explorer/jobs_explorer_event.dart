import 'package:equatable/equatable.dart';

import '../../../../domain/entities/job_filters.dart';

/// What can be done to a job from the explorer.
enum JobTriage {
  save('Save', 'Saved'),
  applied('Mark as applied', 'Marked as applied'),
  rejected('Mark as rejected', 'Marked as rejected'),
  expired('Mark as expired', 'Marked as expired'),
  reactivate('Mark as active again', 'Marked as active'),
  reset('Remove from tracker', 'Removed from the tracker'),
  delete('Delete', 'Deleted');

  const JobTriage(this.label, this.done);
  final String label;
  final String done;
}

sealed class JobsExplorerEvent extends Equatable {
  const JobsExplorerEvent();

  @override
  List<Object?> get props => [];
}

class JobsExplorerStarted extends JobsExplorerEvent {
  const JobsExplorerStarted();
}

class JobsExplorerRefreshed extends JobsExplorerEvent {
  const JobsExplorerRefreshed();
}

class JobsExplorerFiltersChanged extends JobsExplorerEvent {
  const JobsExplorerFiltersChanged(this.filters);
  final JobFilters filters;

  @override
  List<Object?> get props => [filters];
}

/// Typing in the search box (applied after a short pause).
class JobsExplorerQueryChanged extends JobsExplorerEvent {
  const JobsExplorerQueryChanged(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}

class JobsExplorerLoadMore extends JobsExplorerEvent {
  const JobsExplorerLoadMore();
}

class JobsExplorerToggled extends JobsExplorerEvent {
  const JobsExplorerToggled(this.id);
  final String id;

  @override
  List<Object?> get props => [id];
}

class JobsExplorerSelectLoaded extends JobsExplorerEvent {
  const JobsExplorerSelectLoaded();
}

class JobsExplorerSelectionCleared extends JobsExplorerEvent {
  const JobsExplorerSelectionCleared();
}

class JobsExplorerTriaged extends JobsExplorerEvent {
  const JobsExplorerTriaged(this.id, this.action);
  final String id;
  final JobTriage action;

  @override
  List<Object?> get props => [id, action];
}

class JobsExplorerMessageCleared extends JobsExplorerEvent {
  const JobsExplorerMessageCleared();
}
