import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's segmented tabs: a bordered track with a filled indigo thumb.
/// Must sit under a [DefaultTabController] (or pass [controller]).
class SegmentedTabBar extends StatelessWidget {
  const SegmentedTabBar({super.key, required this.labels, this.controller, this.margin = EdgeInsets.zero});

  final List<String> labels;
  final TabController? controller;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
        border: Border.all(color: t.border),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(AppTheme.radius - 2),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: t.onFill,
        unselectedLabelColor: t.subtle,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        splashBorderRadius: BorderRadius.circular(AppTheme.radius - 2),
        tabs: [for (final l in labels) Tab(height: 38, text: l)],
      ),
    );
  }
}
