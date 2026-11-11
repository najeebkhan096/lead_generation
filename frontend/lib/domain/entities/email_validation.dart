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

/// A validation (WhatsApp or email) that stopped before it finished — cancelled,
/// halted for a safety reason, or cut off by a backend restart — and can be
/// resumed from where it left off.
class ValidationRun extends Equatable {
  const ValidationRun({
    required this.id,
    required this.kind,
    required this.status,
    this.collection = 'websiteLeads',
    this.archiveId,
    this.category,
    this.states = const [],
    this.total = 0,
    this.checked = 0,
    this.found = 0,
    this.stoppedReason,
    this.updatedAt,
  });

  final String id;

  /// `whatsapp` or `email`.
  final String kind;

  /// `stopped` (cancelled or halted) or `interrupted` (the backend went away).
  final String status;
  final String collection;

  /// For an Excel archive's validation (`collection == 'archive'`): which archive.
  final String? archiveId;
  final String? category;
  final List<String> states;
  final int total;
  final int checked;
  final int found;
  final String? stoppedReason;
  final DateTime? updatedAt;

  bool get isWhatsApp => kind == 'whatsapp';

  factory ValidationRun.fromJson(Map<String, dynamic> json) => ValidationRun(
        id: (json['id'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? 'whatsapp',
        status: (json['status'] as String?) ?? 'stopped',
        collection: (json['collection'] as String?) ?? 'websiteLeads',
        archiveId: json['archiveId'] as String?,
        category: json['category'] as String?,
        states: [for (final s in (json['states'] as List<dynamic>? ?? const [])) s as String],
        total: (json['total'] as num?)?.toInt() ?? 0,
        checked: (json['checked'] as num?)?.toInt() ?? 0,
        found: (json['found'] as num?)?.toInt() ?? 0,
        stoppedReason: json['stoppedReason'] as String?,
        updatedAt: json['updatedAt'] is num ? DateTime.fromMillisecondsSinceEpoch((json['updatedAt'] as num).toInt()) : null,
      );

  @override
  List<Object?> get props => [id, kind, status, collection, archiveId, category, states, total, checked, found, stoppedReason, updatedAt];
}
