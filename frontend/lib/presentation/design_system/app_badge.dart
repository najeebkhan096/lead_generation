import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_tone.dart';

/// A compact status label: "Active", "Email found", "Contacted".
/// Use [dot] for a quiet status (a colored dot beside plain text).
class AppBadge extends StatelessWidget {
  const AppBadge(
    this.label, {
    super.key,
    this.tone = AppTone.neutral,
    this.icon,
    this.dot = false,
    this.dense = false,
  });

  final String label;
  final AppTone tone;
  final IconData? icon;
  final bool dot;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = tone.onSurface;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.solid, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 11 : 11.5, fontWeight: FontWeight.w600, color: fg, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
