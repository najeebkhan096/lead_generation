import 'package:equatable/equatable.dart';

/// Whether the scraper's Google account is signed in. Scans need it: Google
/// shows anonymous visitors only a few reviews and will not let them sort, so
/// 1-star reviews would be missed.
class MapsSessionStatus extends Equatable {
  const MapsSessionStatus({
    required this.status,
    this.ready = false,
    this.loginInProgress = false,
    this.inUseByScan = false,
    this.detail = '',
  });

  /// signed_in | signed_out | no_profile | locked | unknown | error |
  /// login_in_progress | in_use
  final String status;

  /// A scan can be started.
  final bool ready;

  /// The sign-in window is open on the backend computer.
  final bool loginInProgress;

  /// A running scan holds the Google profile.
  final bool inUseByScan;
  final String detail;

  bool get signedIn => status == 'signed_in';

  factory MapsSessionStatus.fromJson(Map<String, dynamic> json) => MapsSessionStatus(
        status: (json['status'] as String?) ?? 'unknown',
        ready: json['ready'] == true,
        loginInProgress: json['loginInProgress'] == true,
        inUseByScan: json['inUseByScan'] == true,
        detail: (json['detail'] as String?) ?? '',
      );

  @override
  List<Object?> get props => [status, ready, loginInProgress, inUseByScan, detail];
}
