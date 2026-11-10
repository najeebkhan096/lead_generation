import 'package:equatable/equatable.dart';

sealed class JobsScanEvent extends Equatable {
  const JobsScanEvent();

  @override
  List<Object?> get props => [];
}

/// Load the running scans and the history, and start following them.
class JobsScanStarted extends JobsScanEvent {
  const JobsScanStarted();
}

/// A poll tick (or a manual refresh).
class JobsScanRefreshed extends JobsScanEvent {
  const JobsScanRefreshed({this.force = false});
  final bool force;

  @override
  List<Object?> get props => [force];
}

class JobsScanBegin extends JobsScanEvent {
  const JobsScanBegin(this.searchId);
  final String searchId;

  @override
  List<Object?> get props => [searchId];
}

class JobsScanPause extends JobsScanEvent {
  const JobsScanPause(this.runId);
  final String runId;

  @override
  List<Object?> get props => [runId];
}

class JobsScanResume extends JobsScanEvent {
  const JobsScanResume(this.runId);
  final String runId;

  @override
  List<Object?> get props => [runId];
}

class JobsScanStop extends JobsScanEvent {
  const JobsScanStop(this.runId);
  final String runId;

  @override
  List<Object?> get props => [runId];
}

class JobsScanSelected extends JobsScanEvent {
  const JobsScanSelected(this.runId);
  final String? runId;

  @override
  List<Object?> get props => [runId];
}

class JobsScanMoreHistory extends JobsScanEvent {
  const JobsScanMoreHistory();
}

class JobsScanMessageCleared extends JobsScanEvent {
  const JobsScanMessageCleared();
}
