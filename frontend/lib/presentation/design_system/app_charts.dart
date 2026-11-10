import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_tone.dart';

String compactNumber(num n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 10000) return '${(n / 1000).toStringAsFixed(0)}k';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.round().toString();
}

/// "1,204" — thousands separators for full-size numbers.
String groupedNumber(num n) {
  final s = n.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// One bar of an [AppBarChart].
class ChartBar {
  const ChartBar({required this.label, required this.value, required this.tooltip});

  /// Short axis label.
  final String label;
  final double value;

  /// Shown on hover.
  final String tooltip;
}

/// A vertical bar chart with three gridlines, animated bars and hover
/// tooltips. Only for series with real values.
class AppBarChart extends StatelessWidget {
  const AppBarChart({super.key, required this.bars, this.height = 190, this.tone = AppTone.primary});

  final List<ChartBar> bars;
  final double height;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final max = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    // A round ceiling so the gridlines read as tidy numbers.
    final ceiling = max <= 0 ? 1.0 : _niceCeiling(max);
    final labelStyle = TextStyle(fontSize: 11, color: AppTheme.textMuted);
    const axisWidth = 40.0;
    const labelHeight = 22.0;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          for (final f in const [0.0, 0.5, 1.0])
            Positioned(
              left: 0,
              right: 0,
              bottom: labelHeight + (height - labelHeight - 14) * f - 7,
              child: Row(
                children: [
                  SizedBox(width: axisWidth - 6, child: Text(compactNumber(ceiling * f), style: labelStyle, textAlign: TextAlign.right)),
                  const SizedBox(width: 6),
                  Expanded(child: Divider(height: 1, color: f == 0 ? AppTheme.borderStrong : AppTheme.divider)),
                ],
              ),
            ),
          Positioned.fill(
            left: axisWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bar in bars)
                  Expanded(
                    child: Tooltip(
                      message: bar.tooltip,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: bar.value / ceiling),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => FractionallySizedBox(
                                    heightFactor: v.clamp(0.0, 1.0),
                                    child: Container(
                                      constraints: const BoxConstraints(maxWidth: 36, minHeight: 2),
                                      decoration: BoxDecoration(
                                        color: tone.solid,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXs)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: labelHeight,
                            child: Center(child: Text(bar.label, style: labelStyle, maxLines: 1, overflow: TextOverflow.clip)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static double _niceCeiling(double v) {
    var magnitude = 1.0;
    while (magnitude * 10 <= v) {
      magnitude *= 10;
    }
    for (final step in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (v <= step * magnitude) return step * magnitude;
    }
    return 10 * magnitude;
  }
}

/// One slice of a [ShareBar].
class ShareSegment {
  const ShareSegment({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final AppTone tone;
}

/// A single stacked bar showing how a whole divides, with a legend that
/// carries the exact numbers and percentages.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.segments});

  final List<ShareSegment> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (s, e) => s + e.value);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: SizedBox(
            height: 10,
            child: total == 0
                ? ColoredBox(color: AppTheme.neutral200)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in segments)
                        if (s.value > 0)
                          Expanded(
                            flex: s.value,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: ColoredBox(color: s.tone.solid),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        for (final s in segments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: s.tone.solid, shape: BoxShape.circle)),
                const SizedBox(width: AppSpace.sm + 2),
                Expanded(child: Text(s.label, style: text.bodyMedium?.copyWith(color: AppTheme.textPrimary))),
                Text(groupedNumber(s.value), style: AppText.cell.copyWith(fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 52,
                  child: Text(
                    total == 0 ? '—' : '${(s.value * 100 / total).round()}%',
                    textAlign: TextAlign.right,
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A label, a count and a proportional bar — a ranked list (top categories).
class RankedBar extends StatelessWidget {
  const RankedBar({super.key, required this.label, required this.count, required this.fraction, this.tone = AppTone.primary});

  final String label;
  final int count;
  final double fraction;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cell.copyWith(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: AppSpace.sm),
            Text(groupedNumber(count), style: AppText.cell.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Stack(
            children: [
              Container(height: 6, color: tone.track),
              TweenAnimationBuilder<double>(
                tween: Tween(end: fraction.clamp(0.03, 1.0)),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(height: 6, color: tone.solid),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
