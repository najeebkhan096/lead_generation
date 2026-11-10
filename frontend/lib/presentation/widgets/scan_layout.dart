import 'package:flutter/material.dart';

import '../design_system/design_system.dart';

/// The structure every scanning screen shares: the configuration sections on
/// the left, a summary card with the scan's controls on the right (below the
/// sections on a narrow window).
class ScanLayout extends StatelessWidget {
  const ScanLayout({super.key, required this.sections, required this.summary, this.summaryWidth = 360});

  final List<Widget> sections;
  final Widget summary;
  final double summaryWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpace.xl),
              sections[i],
            ],
          ],
        );
        if (c.maxWidth < 980) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: AppSpace.xl), summary]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpace.xl),
            SizedBox(width: summaryWidth, child: summary),
          ],
        );
      },
    );
  }
}

/// One "label ... value" line of a scan summary.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: AppSpace.sm + 2),
          Text(label, style: text.bodyMedium),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.cell.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
