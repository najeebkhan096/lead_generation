import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A page's title block: title, one line of context, and the page's actions on
/// the right (they wrap under the title on narrow windows).
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.onBack, this.leading});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(AppIcons.arrowLeft)),
          const SizedBox(width: AppSpace.sm),
        ],
        if (leading != null) ...[leading!, const SizedBox(width: AppSpace.md)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.displaySmall),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: text.bodyLarge),
              ],
            ],
          ),
        ),
      ],
    );

    if (actions.isEmpty) return titleBlock;
    return LayoutBuilder(
      builder: (context, c) {
        final actionWrap = Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: actions);
        if (c.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleBlock, const SizedBox(height: AppSpace.md), actionWrap],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: titleBlock), const SizedBox(width: AppSpace.lg), actionWrap],
        );
      },
    );
  }
}

/// A scrolling page: gutter that follows the window, content capped at a
/// readable width, optional pull-to-refresh. For pages built from a list of
/// sections.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.onRefresh,
    this.onBack,
    this.maxWidth = AppSpace.pageMaxWidth,
    this.spacing = AppSpace.xl,
  });

  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onBack;
  final double maxWidth;

  /// Vertical gap between [children].
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = AppSpace.pageGutter(width);
    final body = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, gutter, gutter, AppSpace.xxxl),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                PageHeader(title: title!, subtitle: subtitle, actions: actions, onBack: onBack),
                SizedBox(height: spacing),
              ],
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: onRefresh == null ? body : RefreshIndicator(onRefresh: onRefresh!, child: body),
    );
  }
}

/// A responsive grid of equal tiles. Columns are chosen so the last row is
/// never a lone orphan: with [evenRows] (the default) only column counts that
/// divide the number of tiles are used (6 tiles → 6, 3, 2 or 1 columns).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 220,
    this.spacing = AppSpace.lg,
    this.evenRows = true,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final bool evenRows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = children.isEmpty ? 1 : children.length;
        var columns = ((c.maxWidth + spacing) / (minTileWidth + spacing)).floor().clamp(1, n);
        if (evenRows) {
          while (columns > 1 && n % columns != 0) {
            columns--;
          }
        }
        final tileWidth = (c.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: tileWidth, child: child)],
        );
      },
    );
  }
}
