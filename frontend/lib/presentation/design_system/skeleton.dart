import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_card.dart';

/// Shares one pulse animation between every [Skeleton] below it, so a screen
/// full of placeholders costs a single ticker.
class SkeletonScope extends StatefulWidget {
  const SkeletonScope({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonScope> createState() => _SkeletonScopeState();
}

class _SkeletonScopeState extends State<SkeletonScope> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Pulse(animation: _controller, child: widget.child);
}

class _Pulse extends InheritedWidget {
  const _Pulse({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Pulse>()?.animation;

  @override
  bool updateShouldNotify(_Pulse old) => animation != old.animation;
}

/// A loading placeholder block. Put several inside a [SkeletonScope].
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = AppTheme.radiusSm});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pulse = _Pulse.maybeOf(context);
    Widget block(double t) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Color.lerp(AppTheme.neutral100, AppTheme.neutral200, t),
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    if (pulse == null) return block(0.5);
    return AnimatedBuilder(animation: pulse, builder: (_, _) => block(pulse.value));
  }
}

/// A grid-friendly placeholder for a stat card.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 112});

  final double height;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        height: height - AppSpace.lg * 2,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(width: 90, height: 12),
            Spacer(),
            Skeleton(width: 120, height: 26),
          ],
        ),
      ),
    );
  }
}

/// A list of placeholder table rows.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: [
                  const Skeleton(width: 32, height: 32, radius: AppTheme.radius),
                  const SizedBox(width: AppSpace.md),
                  const Expanded(flex: 3, child: Skeleton(height: 12)),
                  const SizedBox(width: AppSpace.xl),
                  const Expanded(flex: 2, child: Skeleton(height: 12)),
                  const SizedBox(width: AppSpace.xl),
                  const Expanded(flex: 1, child: Skeleton(height: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
