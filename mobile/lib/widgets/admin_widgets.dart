import 'package:flutter/material.dart';

import '../models/sale.dart';
import '../services/admin_data.dart';
import '../theme/app_theme.dart';

/// Pushes [page] with the same [AdminData] the caller sees. Pushed routes
/// sit above the tab tree, so they would not inherit [AdminScope] on their
/// own.
Future<T?> pushAdminPage<T>(BuildContext context, Widget page) {
  final data = AdminScope.read(context);
  return Navigator.of(context).push<T>(
    MaterialPageRoute(builder: (_) => AdminScope(data: data, child: page)),
  );
}

/// Quiet semantic color pairs for pills, icon holders and bars.
/// [deep] is the darker indigo: the payment step, next to [accent] (removal).
enum Tone { neutral, accent, deep, success, danger }

extension ToneColors on Tone {
  (Color background, Color foreground) colors(AppTokens t) => switch (this) {
        Tone.neutral => (t.neutralTint, t.subtle),
        Tone.accent => (t.accentTint, t.accentText),
        Tone.deep => (t.accentTint, t.accentTextStrong),
        Tone.success => (t.sageTint, t.sageText),
        // Red on a slate tint misses AA (3.9:1); red on the card surface
        // passes, so danger pills are outlined instead of tinted.
        Tone.danger => (t.surface, t.danger),
      };

  Color solid(AppTokens t) => switch (this) {
        Tone.neutral => t.neutralTintStrong,
        Tone.accent => t.accent,
        Tone.deep => t.accentTextStrong,
        Tone.success => t.sage,
        Tone.danger => t.danger,
      };
}

Tone toneOfStatus(SaleStatus s) => switch (s) {
      SaleStatus.newSale => Tone.neutral,
      SaleStatus.inProgress => Tone.accent,
      SaleStatus.payment => Tone.deep,
      SaleStatus.completed => Tone.success,
      SaleStatus.cancelled => Tone.danger,
    };

/// White card with a hairline border; tappable when [onTap] is set.
class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.margin});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(AppTheme.radiusCard);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: t.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small rounded label: a status, role, or count.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = Tone.neutral, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(context.tokens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: tone == Tone.danger ? Border.all(color: fg.withValues(alpha: 0.4)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.2)),
        ],
      ),
    );
  }
}

/// Rounded-square icon holder.
class IconHolder extends StatelessWidget {
  const IconHolder({super.key, required this.icon, this.tone = Tone.accent, this.size = 40});

  final IconData icon;
  final Tone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone.colors(context.tokens);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// Headline number with a label — the building block of every stats grid.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, required this.icon, this.tone = Tone.accent, this.caption, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconHolder(icon: icon, tone: tone, size: 34),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: t.ink)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// A two-column grid of [KpiTile]s that sizes to its content (no fixed
/// aspect ratio to overflow at large text scales).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 12),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ],
        ),
      ));
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: text.titleMedium)),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(actionLabel!, style: TextStyle(color: t.accentText, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Initials in a tinted circle, or the account photo when there is one.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.photoUrl, this.size = 42});

  final String name;
  final String? photoUrl;
  final double size;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: t.accentTint,
      foregroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
      child: Text(_initials, style: TextStyle(color: t.accentTextStrong, fontWeight: FontWeight.w700, fontSize: size * 0.34)),
    );
  }
}

/// Proportional bar: one coloured segment per entry.
class SegmentBar extends StatelessWidget {
  const SegmentBar({super.key, required this.segments});

  final List<(int count, Tone tone)> segments;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = segments.fold<int>(0, (a, s) => a + s.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: SizedBox(
        height: 10,
        child: total == 0
            ? ColoredBox(color: t.neutralTint)
            : Row(
                children: [
                  for (final (count, tone) in segments)
                    if (count > 0) Expanded(flex: count, child: ColoredBox(color: tone.solid(t))),
                ],
              ),
      ),
    );
  }
}

/// A colour key line for [SegmentBar]: dot, label, value.
class LegendRow extends StatelessWidget {
  const LegendRow({super.key, required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: tone.solid(t), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(value, style: text.titleSmall),
        ],
      ),
    );
  }
}

/// A label and value on one line, for detail cards.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.valueColor, this.bold = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.titleSmall?.copyWith(color: valueColor, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconHolder(icon: icon, tone: Tone.neutral, size: 56),
            const SizedBox(height: 16),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconHolder(icon: AppIcons.alert, tone: Tone.danger, size: 56),
            const SizedBox(height: 16),
            Text('Couldn\'t load data', style: text.titleMedium),
            const SizedBox(height: 6),
            Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// Wraps a tab body: spinner on first load, an error with retry when
/// nothing has loaded, otherwise [builder] inside pull-to-refresh.
class AdminLoadGate extends StatelessWidget {
  const AdminLoadGate({super.key, required this.builder});

  final Widget Function(BuildContext context, AdminData data) builder;

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    if (!data.loadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data.error != null && !data.hasData) {
      return ErrorState(message: data.error!, onRetry: data.load);
    }
    return RefreshIndicator(
      onRefresh: data.load,
      child: builder(context, data),
    );
  }
}

/// Shows a failure from an admin action without blocking the screen.
void showAdminError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final message = error.toString().replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showAdminMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmAdminAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final t = context.tokens;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: destructive ? TextStyle(color: t.danger) : null),
        ),
      ],
    ),
  );
  return result == true;
}
