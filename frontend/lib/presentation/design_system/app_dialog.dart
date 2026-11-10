import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_button.dart';
import 'app_feedback.dart';
import 'app_tone.dart';

/// Shows [builder]'s dialog with the console's transition (a quick fade and
/// 4% scale-up).
Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder, bool barrierDismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: AppTheme.isDark ? 0.6 : 0.4),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, _) => SafeArea(child: Center(child: Builder(builder: builder))),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// The dialog frame: title, optional message/body, and a right-aligned action row.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.icon,
    this.tone = AppTone.primary,
    this.width = 440,
  });

  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;
  final IconData? icon;
  final AppTone tone;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Material(
          color: AppTheme.surfaceElevated,
          elevation: 0,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.shadowPopover,
            ),
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[IconTile(icon!, tone: tone), const SizedBox(width: AppSpace.md + 2)],
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: icon == null ? 0 : 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: text.titleLarge),
                            if (message != null) ...[
                              const SizedBox(height: AppSpace.sm - 2),
                              Text(message!, style: text.bodyMedium),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (content != null) ...[const SizedBox(height: AppSpace.lg), Flexible(child: content!)],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpace.sm),
                        actions[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A yes/no question. Resolves `true` only when confirmed. Pass
/// [destructive] for deletes.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showAppDialog<bool>(
    context,
    builder: (ctx) => AppDialog(
      title: title,
      message: message,
      icon: destructive ? AppIcons.trash : AppIcons.alert,
      tone: destructive ? AppTone.error : AppTone.primary,
      actions: [
        AppButton.outlined(label: cancelLabel, onPressed: () => Navigator.pop(ctx, false)),
        destructive
            ? AppButton.destructive(label: confirmLabel, onPressed: () => Navigator.pop(ctx, true))
            : AppButton.primary(label: confirmLabel, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return result == true;
}
