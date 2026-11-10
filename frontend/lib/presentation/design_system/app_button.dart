import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum AppButtonVariant { primary, secondary, outlined, text, destructive }

enum AppButtonSize { sm, md }

/// The console's one button. Variants:
///
///  * `primary`     – the main action of a view (one per area)
///  * `secondary`   – a quiet filled button
///  * `outlined`    – an equal-weight alternative
///  * `text`        – an inline action
///  * `destructive` – deletes / irreversible actions
///
/// [loading] swaps the icon for a spinner and disables the button; a `null`
/// [onPressed] disables it.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  });

  const AppButton.primary({super.key, required this.label, required this.onPressed, this.size = AppButtonSize.md, this.icon, this.trailingIcon, this.loading = false, this.fullWidth = false})
      : variant = AppButtonVariant.primary;

  const AppButton.secondary({super.key, required this.label, required this.onPressed, this.size = AppButtonSize.md, this.icon, this.trailingIcon, this.loading = false, this.fullWidth = false})
      : variant = AppButtonVariant.secondary;

  const AppButton.outlined({super.key, required this.label, required this.onPressed, this.size = AppButtonSize.md, this.icon, this.trailingIcon, this.loading = false, this.fullWidth = false})
      : variant = AppButtonVariant.outlined;

  const AppButton.text({super.key, required this.label, required this.onPressed, this.size = AppButtonSize.md, this.icon, this.trailingIcon, this.loading = false, this.fullWidth = false})
      : variant = AppButtonVariant.text;

  const AppButton.destructive({super.key, required this.label, required this.onPressed, this.size = AppButtonSize.md, this.icon, this.trailingIcon, this.loading = false, this.fullWidth = false})
      : variant = AppButtonVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final small = size == AppButtonSize.sm;
    final enabled = onPressed != null && !loading;

    final style = _style(small);
    final iconSize = small ? 15.0 : 17.0;
    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(strokeWidth: 2, color: _spinnerColor),
          )
        else if (icon != null)
          Icon(icon, size: iconSize),
        if (loading || icon != null) SizedBox(width: small ? 6 : 8),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (trailingIcon != null) ...[SizedBox(width: small ? 6 : 8), Icon(trailingIcon, size: iconSize)],
      ],
    );

    final handler = enabled ? onPressed : null;
    final button = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.secondary || AppButtonVariant.destructive =>
        FilledButton(onPressed: handler, style: style, child: child),
      AppButtonVariant.outlined => OutlinedButton(onPressed: handler, style: style, child: child),
      AppButtonVariant.text => TextButton(onPressed: handler, style: style, child: child),
    };
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }

  Color get _spinnerColor => switch (variant) {
        AppButtonVariant.primary || AppButtonVariant.destructive => AppTheme.onPrimary,
        AppButtonVariant.secondary => AppTheme.textSecondary,
        _ => AppTheme.primary,
      };

  ButtonStyle _style(bool small) {
    final sizing = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(small ? 40 : 64, small ? 32 : 40)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 6 : 10)),
      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: small ? 12.5 : 13.5, fontWeight: FontWeight.w600)),
    );
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.outlined:
      case AppButtonVariant.text:
        return sizing;
      case AppButtonVariant.secondary:
        return sizing.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppTheme.neutral100;
            if (s.contains(WidgetState.pressed)) return AppTheme.neutral300;
            if (s.contains(WidgetState.hovered)) return AppTheme.neutral200;
            return AppTheme.neutral100;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled) ? AppTheme.textMuted.withValues(alpha: 0.6) : AppTheme.textPrimary),
        );
      case AppButtonVariant.destructive:
        return sizing.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return AppTheme.error500.withValues(alpha: 0.4);
            if (s.contains(WidgetState.pressed)) return AppTheme.error800;
            if (s.contains(WidgetState.hovered)) return AppTheme.isDark ? AppTheme.error600 : AppTheme.error600;
            return AppTheme.error500;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
        );
    }
  }
}

/// An icon-only button with a tooltip (always required: it is the label).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.size = 36,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final bool selected;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: loading ? null : onPressed,
      style: IconButton.styleFrom(
        minimumSize: Size(size, size),
        fixedSize: Size(size, size),
        backgroundColor: selected ? AppTheme.primary100 : null,
        foregroundColor: selected ? AppTheme.primary700 : (color ?? AppTheme.textSecondary),
      ),
      icon: loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
    );
  }
}
