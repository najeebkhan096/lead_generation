import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/email_validation_snapshot.dart';

/// Where every business in the last run ended up — so "12 verified" isn't
/// the only thing a run reports about the other businesses it checked.
class EmailOutcomeSummary extends StatelessWidget {
  const EmailOutcomeSummary({super.key, required this.snapshot});

  final EmailValidationSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int count, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
          child: Text(
            '$count $label',
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('verified', snapshot.validCount, AppTheme.sage100, AppTheme.sage800),
        if (snapshot.reusedCount > 0)
          chip('already verified', snapshot.reusedCount, AppTheme.sage100, AppTheme.sage800),
        chip('no email on site', snapshot.noEmailCount, AppTheme.neutral100, AppTheme.neutral700),
        chip('failed verification', snapshot.invalidCount, AppTheme.accent100, AppTheme.accent800),
        chip('unreachable', snapshot.errorCount, AppTheme.neutral100, AppTheme.neutral700),
      ],
    );
  }
}
