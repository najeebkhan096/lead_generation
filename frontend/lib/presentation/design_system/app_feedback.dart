import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_button.dart';
import 'app_tone.dart';

/// An icon in a tinted rounded square — the leading mark of empty states,
/// alerts and list rows.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tone = AppTone.primary, this.size = 40});

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.surface, borderRadius: BorderRadius.circular(size > 36 ? AppTheme.radiusMd : AppTheme.radius)),
      child: Icon(icon, size: size * 0.45, color: tone.onSurface),
    );
  }
}

/// Nothing to show — say why and what to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tone = AppTone.primary,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final AppTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? AppSpace.xl : AppSpace.xxxl, horizontal: AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTile(icon, tone: tone, size: 48),
              const SizedBox(height: AppSpace.lg),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpace.sm - 2),
                Text(message!, style: text.bodyMedium, textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// An inline notice: info, success, warning or error.
class AppAlert extends StatelessWidget {
  const AppAlert({
    super.key,
    required this.message,
    this.title,
    this.tone = AppTone.info,
    this.icon,
    this.actions = const [],
    this.onDismiss,
  });

  final String? title;
  final String message;
  final AppTone tone;
  final IconData? icon;
  final List<Widget> actions;
  final VoidCallback? onDismiss;

  IconData get _icon =>
      icon ??
      switch (tone) {
        AppTone.success => AppIcons.checkCircle,
        AppTone.warning => AppIcons.triangleAlert,
        AppTone.error => AppIcons.alert,
        _ => AppIcons.alert,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(_icon, size: 18, color: tone.onSurface),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: text.titleSmall?.copyWith(color: tone.onSurface)),
                if (title != null) const SizedBox(height: 2),
                Text(message, style: text.bodyMedium?.copyWith(color: tone.onSurface)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm + 2),
                  Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: actions),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            AppIconButton(icon: AppIcons.close, tooltip: 'Dismiss', onPressed: onDismiss, size: 28),
        ],
      ),
    );
  }
}

/// A determinate (0–1) or indeterminate (`null`) progress bar whose fill
/// animates smoothly between values.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, this.value, this.tone = AppTone.primary, this.height = 6});

  final double? value;
  final AppTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusPill);
    if (value == null) {
      return ClipRRect(
        borderRadius: radius,
        child: LinearProgressIndicator(minHeight: height, color: tone.solid, backgroundColor: tone.track),
      );
    }
    final target = value!.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        color: tone.track,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: target),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => FractionallySizedBox(
            widthFactor: v,
            child: Container(decoration: BoxDecoration(color: tone.solid, borderRadius: radius)),
          ),
        ),
      ),
    );
  }
}

/// A centered spinner for a view that is loading.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (label != null) ...[
              const SizedBox(height: AppSpace.md),
              Text(label!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
