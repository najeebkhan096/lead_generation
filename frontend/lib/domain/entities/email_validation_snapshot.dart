import 'package:equatable/equatable.dart';

/// One business's outcome from a bulk email validation run.
class EmailValidationResult extends Equatable {
  const EmailValidationResult({
    required this.valid,
    this.email,
    this.emails = const [],
    this.source,
    this.foundOn,
    this.result,
    this.reason,
    this.error,
  });

  /// A deliverable address was found for this business.
  final bool valid;

  /// The best address found (the verified one when [valid]).
  final String? email;

  /// Every address found on the site, best first.
  final List<String> emails;

  /// Where on the site [email] was found — see `emailSourceLabel`.
  final String? source;

  /// The page [email] was read from (web-search mode).
  final String? foundOn;

  /// Verifier verdict for [email]: `valid | invalid | risky | unknown`.
  final String? result;
  final String? reason;

  /// Set when the site couldn't be reached (or the save failed) — distinct
  /// from "reachable, but no email on it" (`reason == 'no_email_found'`).
  final String? error;

  factory EmailValidationResult.fromJson(Map<String, dynamic> json) {
    return EmailValidationResult(
      valid: json['valid'] == true,
      email: json['email'] as String?,
      emails: ((json['emails'] as List<dynamic>?) ?? const []).whereType<String>().toList(),
      source: json['source'] as String?,
      foundOn: json['foundOn'] as String?,
      result: json['result'] as String?,
      reason: json['reason'] as String?,
      error: json['error'] as String?,
    );
  }

  @override
  List<Object?> get props => [valid, email, emails, source, foundOn, result, reason, error];
}

/// Progress of a bulk email validation job, polled while it runs — mirrors
/// `WhatsAppValidationSnapshot`, with the extra "no email on the site"
/// bucket an email check has.
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
    this.currentLeadBusiness,
    this.results = const {},
    this.elapsedMs = 0,
    this.stoppedReason,
  });

  final bool active;
  final String status; // idle | running | done | cancelled
  final int total;
  final int checked;

  /// A deliverable email was found.
  final int validCount;

  /// An email was found but failed verification (no MX, disposable, …).
  final int invalidCount;

  /// The site loaded but lists no public email.
  final int noEmailCount;

  /// The site couldn't be reached.
  final int errorCount;
  final String? currentLeadBusiness;
  final Map<String, EmailValidationResult> results;
  final int elapsedMs;
  final String? stoppedReason;

  bool get hasJob => status != 'idle';

  factory EmailValidationSnapshot.fromJson(Map<String, dynamic> json) {
    final resultsJson = (json['results'] as Map<String, dynamic>?) ?? const {};
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
      currentLeadBusiness: (json['currentLead'] as Map<String, dynamic>?)?['business'] as String?,
      results: resultsJson.map(
        (k, v) => MapEntry(k, EmailValidationResult.fromJson(v as Map<String, dynamic>)),
      ),
      elapsedMs: n('elapsedMs'),
      stoppedReason: json['stoppedReason'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [active, status, total, checked, validCount, invalidCount, noEmailCount, errorCount];
}
