import 'package:equatable/equatable.dart';

/// One business's outcome from an email lookup run.
class EmailCheckEntry extends Equatable {
  const EmailCheckEntry({required this.valid, this.email, this.foundOn, this.reason, this.error});

  final bool valid;
  final String? email;

  /// The page the address was found on.
  final String? foundOn;
  final String? reason;
  final String? error;

  factory EmailCheckEntry.fromJson(Map<String, dynamic> json) => EmailCheckEntry(
        valid: json['valid'] == true,
        email: json['email'] as String?,
        foundOn: json['foundOn'] as String?,
        reason: json['reason'] as String?,
        error: json['error'] as String?,
      );

  @override
  List<Object?> get props => [valid, email, foundOn, reason, error];
}

/// Progress of the no-website email lookup, polled while it runs.
class EmailValidationSnapshot extends Equatable {
  const EmailValidationSnapshot({
    required this.active,
    required this.status,
    this.total = 0,
    this.checked = 0,
    this.validCount = 0,
    this.invalidCount = 0,
    this.noEmailCount = 0,
    this.errorCount = 0,
    this.currentBusiness,
    this.results = const {},
    this.stoppedReason,
  });

  final bool active;
  final String status; // idle | running | done | cancelled
  final int total;
  final int checked;

  /// A deliverable address was found.
  final int validCount;

  /// An address was found but failed verification.
  final int invalidCount;

  /// The lookup worked, nothing found.
  final int noEmailCount;
  final int errorCount;
  final String? currentBusiness;
  final Map<String, EmailCheckEntry> results;
  final String? stoppedReason;

  bool get hasJob => status != 'idle';

  factory EmailValidationSnapshot.fromJson(Map<String, dynamic> json) {
    final results = (json['results'] as Map<String, dynamic>?) ?? const {};
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return EmailValidationSnapshot(
      active: json['active'] == true,
      status: (json['status'] as String?) ?? 'idle',
      total: n('total'),
      checked: n('checked'),
      validCount: n('validCount'),
      invalidCount: n('invalidCount'),
      noEmailCount: n('noEmailCount'),
      errorCount: n('errorCount'),
      currentBusiness: (json['currentLead'] as Map<String, dynamic>?)?['business'] as String?,
      results: results.map((k, v) => MapEntry(k, EmailCheckEntry.fromJson(v as Map<String, dynamic>))),
      stoppedReason: json['stoppedReason'] as String?,
    );
  }

  @override
  List<Object?> get props => [active, status, total, checked, validCount, invalidCount, noEmailCount, errorCount, currentBusiness, stoppedReason];
}
