import 'package:equatable/equatable.dart';

enum WhatsAppWebConnectionStatus {
  disconnected,
  initializing,
  qr,
  authenticated,
  ready,
  authFailure,
  error;

  static WhatsAppWebConnectionStatus fromJson(String? value) {
    switch (value) {
      case 'disconnected':
        return WhatsAppWebConnectionStatus.disconnected;
      case 'initializing':
        return WhatsAppWebConnectionStatus.initializing;
      case 'qr':
        return WhatsAppWebConnectionStatus.qr;
      case 'authenticated':
        return WhatsAppWebConnectionStatus.authenticated;
      case 'ready':
        return WhatsAppWebConnectionStatus.ready;
      case 'auth_failure':
        return WhatsAppWebConnectionStatus.authFailure;
      default:
        return WhatsAppWebConnectionStatus.error;
    }
  }

  bool get isConnecting =>
      this == WhatsAppWebConnectionStatus.initializing || this == WhatsAppWebConnectionStatus.qr;
}

/// How much of today's safe WhatsApp-check budget is left, whether the
/// linked device is still in its warm-up period, and whether checks are
/// paused for a cooldown or after repeated failures — mirrors the backend's
/// `whatsappSafety.getSafetyStatus()`.
class WhatsAppSafetyStatus extends Equatable {
  const WhatsAppSafetyStatus({
    this.checksToday = 0,
    this.dailyCap = 0,
    this.remainingToday = 0,
    this.warmUpActive = false,
    this.warmUpDaysRemaining = 0,
    this.cooldownActive = false,
    this.cooldownRemainingMs = 0,
    this.circuitOpen = false,
    this.circuitResetInMs = 0,
  });

  final int checksToday;
  final int dailyCap;
  final int remainingToday;
  final bool warmUpActive;
  final int warmUpDaysRemaining;
  final bool cooldownActive;
  final int cooldownRemainingMs;
  final bool circuitOpen;
  final int circuitResetInMs;

  /// Whether a bulk validation run could start right now.
  bool get canRunNow => remainingToday > 0 && !cooldownActive && !circuitOpen;

  /// Short human-readable reason a bulk run is blocked, or null if it isn't.
  String? get blockedReason {
    if (circuitOpen) {
      return 'Paused after repeated failures — resumes in ${(circuitResetInMs / 60000).ceil()} min';
    }
    if (cooldownActive) {
      return 'Cooling down — resumes in ${(cooldownRemainingMs / 1000).ceil()}s';
    }
    if (remainingToday <= 0) return 'Daily check limit reached — resets at midnight UTC';
    return null;
  }

  factory WhatsAppSafetyStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const WhatsAppSafetyStatus();
    final warmUp = json['warmUp'] as Map<String, dynamic>? ?? const {};
    final cooldown = json['cooldown'] as Map<String, dynamic>? ?? const {};
    return WhatsAppSafetyStatus(
      checksToday: (json['checksToday'] as num?)?.toInt() ?? 0,
      dailyCap: (json['dailyCap'] as num?)?.toInt() ?? 0,
      remainingToday: (json['remainingToday'] as num?)?.toInt() ?? 0,
      warmUpActive: warmUp['active'] == true,
      warmUpDaysRemaining: (warmUp['daysRemaining'] as num?)?.toInt() ?? 0,
      cooldownActive: cooldown['active'] == true,
      cooldownRemainingMs: (cooldown['remainingMs'] as num?)?.toInt() ?? 0,
      circuitOpen: json['circuitOpen'] == true,
      circuitResetInMs: (json['circuitResetInMs'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        checksToday,
        dailyCap,
        remainingToday,
        warmUpActive,
        warmUpDaysRemaining,
        cooldownActive,
        cooldownRemainingMs,
        circuitOpen,
        circuitResetInMs,
      ];
}

/// Live status of the backend's single WhatsApp Web session.
class WhatsAppWebStatus extends Equatable {
  const WhatsAppWebStatus({
    required this.status,
    this.qrDataUrl,
    this.error,
    this.phoneNumber,
    this.pushname,
    this.safety = const WhatsAppSafetyStatus(),
  });

  final WhatsAppWebConnectionStatus status;
  final String? qrDataUrl;
  final String? error;
  final String? phoneNumber;
  final String? pushname;
  final WhatsAppSafetyStatus safety;

  bool get isReady => status == WhatsAppWebConnectionStatus.ready;

  factory WhatsAppWebStatus.fromJson(Map<String, dynamic> json) {
    return WhatsAppWebStatus(
      status: WhatsAppWebConnectionStatus.fromJson(json['status'] as String?),
      qrDataUrl: json['qrDataUrl'] as String?,
      error: json['error'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      pushname: json['pushname'] as String?,
      safety: WhatsAppSafetyStatus.fromJson(json['safety'] as Map<String, dynamic>?),
    );
  }

  @override
  List<Object?> get props => [status, qrDataUrl, error, phoneNumber, pushname, safety];
}

/// One lead's outcome from a bulk validation run.
class WhatsAppCheckResultEntry extends Equatable {
  const WhatsAppCheckResultEntry({required this.valid, this.error});

  final bool valid;
  final String? error;

  factory WhatsAppCheckResultEntry.fromJson(Map<String, dynamic> json) {
    return WhatsAppCheckResultEntry(
      valid: json['valid'] == true,
      error: json['error'] as String?,
    );
  }

  @override
  List<Object?> get props => [valid, error];
}

/// Progress of a bulk WhatsApp validation job, polled while it runs.
class WhatsAppValidationSnapshot extends Equatable {
  const WhatsAppValidationSnapshot({
    required this.active,
    required this.status,
    this.total = 0,
    this.checked = 0,
    this.validCount = 0,
    this.invalidCount = 0,
    this.errorCount = 0,
    this.currentLeadBusiness,
    this.results = const {},
    this.elapsedMs = 0,
  });

  final bool active;
  final String status; // idle | running | done | cancelled
  final int total;
  final int checked;
  final int validCount;
  final int invalidCount;
  final int errorCount;
  final String? currentLeadBusiness;
  final Map<String, WhatsAppCheckResultEntry> results;
  final int elapsedMs;

  bool get hasJob => status != 'idle';

  factory WhatsAppValidationSnapshot.fromJson(Map<String, dynamic> json) {
    final resultsJson = (json['results'] as Map<String, dynamic>?) ?? const {};
    return WhatsAppValidationSnapshot(
      active: json['active'] == true,
      status: (json['status'] as String?) ?? 'idle',
      total: (json['total'] as num?)?.toInt() ?? 0,
      checked: (json['checked'] as num?)?.toInt() ?? 0,
      validCount: (json['validCount'] as num?)?.toInt() ?? 0,
      invalidCount: (json['invalidCount'] as num?)?.toInt() ?? 0,
      errorCount: (json['errorCount'] as num?)?.toInt() ?? 0,
      currentLeadBusiness: (json['currentLead'] as Map<String, dynamic>?)?['business'] as String?,
      results: resultsJson.map(
        (k, v) => MapEntry(k, WhatsAppCheckResultEntry.fromJson(v as Map<String, dynamic>)),
      ),
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [active, status, total, checked, validCount, invalidCount, errorCount];
}
