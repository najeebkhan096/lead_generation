import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_card.dart';
import 'app_tone.dart';
import 'skeleton.dart';

/// A headline number: label, big value, an icon tile, and an optional [delta]
/// (only pass one when there is real data behind it) or [hint].
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = AppTone.primary,
    this.hint,
    this.delta,
    this.deltaPositive = true,
    this.onTap,
    this.loading = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final AppTone tone;
  final String? hint;

  /// e.g. "+12% this week". Shown green when [deltaPositive], red otherwise.
  final String? delta;
  final bool deltaPositive;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: text.labelMedium?.copyWith(color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: tone.surface, borderRadius: BorderRadius.circular(AppTheme.radius)),
                child: Icon(icon, size: 17, color: tone.onSurface),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (loading)
            const Skeleton(width: 96, height: 28)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppText.stat),
            ),
          const SizedBox(height: AppSpace.sm),
          // Always one line tall, so a row of cards stays level.
          SizedBox(
            height: 16,
            child: delta != null
                ? Text(
                    delta!,
                    maxLines: 1,
                    style: text.labelMedium?.copyWith(color: deltaPositive ? AppTheme.success700 : AppTheme.error700),
                  )
                : Text(hint ?? '', style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
