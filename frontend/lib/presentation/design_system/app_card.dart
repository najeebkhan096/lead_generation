import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The console's surface: white (navy in dark mode), hairline border, 12px
/// radius. With [onTap] it responds to hover and press.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.color,
    this.borderColor,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  /// Clips children to the rounded corners (tables, full-bleed headers).
  final bool clip;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final radius = BorderRadius.circular(AppTheme.radiusCard);
    final decoration = BoxDecoration(
      color: widget.color ?? AppTheme.surface,
      borderRadius: radius,
      border: Border.all(
        color: widget.borderColor ?? (interactive && _hover ? AppTheme.primary300 : AppTheme.border),
      ),
      boxShadow: interactive && _hover ? AppTheme.shadowRaised : AppTheme.shadowCard,
    );

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (interactive) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: radius, onTap: widget.onTap, child: content),
      );
    }

    return MouseRegion(
      onEnter: interactive ? (_) => setState(() => _hover = true) : null,
      onExit: interactive ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: decoration,
        clipBehavior: widget.clip || interactive ? Clip.antiAlias : Clip.none,
        child: content,
      ),
    );
  }
}

/// A card with a titled header row: title, optional subtitle, trailing actions,
/// then the body.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.icon,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.divided = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// A hairline between the header and the body.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md + 2, AppSpace.lg, AppSpace.md + 2),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppTheme.textMuted),
                  const SizedBox(width: AppSpace.sm + 2),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (divided) Divider(height: 1, color: AppTheme.divider),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
