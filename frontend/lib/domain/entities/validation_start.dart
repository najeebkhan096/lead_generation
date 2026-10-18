import 'package:equatable/equatable.dart';

/// What the backend decided to do when a validation run was requested.
///
/// A run never repeats work the system already has an answer for, so the
/// number of businesses *processed* can be smaller than the number
/// *selected* — this says where the difference went.
class ValidationStart extends Equatable {
  const ValidationStart({
    this.total = 0,
    this.reused = 0,
    this.alreadyChecked = 0,
  });

  /// Businesses the run will actually check.
  final int total;

  /// Already verified earlier — included in the results as verified, not
  /// checked again.
  final int reused;

  /// Checked recently and not on WhatsApp — skipped. "Re-check" overrides this.
  final int alreadyChecked;

  bool get skippedAnything => reused > 0 || alreadyChecked > 0;

  factory ValidationStart.fromJson(Map<String, dynamic> json) {
    int n(String k) => (json[k] as num?)?.toInt() ?? 0;
    return ValidationStart(
      total: n('total'),
      reused: n('reused'),
      alreadyChecked: n('alreadyChecked'),
    );
  }

  /// One-line explanation for a snackbar, or `null` when nothing was skipped.
  String? get summary {
    final parts = <String>[
      if (reused > 0) '$reused already verified (included)',
      if (alreadyChecked > 0) '$alreadyChecked checked before (skipped)',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  List<Object?> get props => [total, reused, alreadyChecked];
}

/// Everything selected was already checked and nothing new was found, so
/// there is nothing to run — unless the user chooses to re-check.
class AlreadyCheckedException implements Exception {
  const AlreadyCheckedException(this.message);

  final String message;

  @override
  String toString() => message;
}
