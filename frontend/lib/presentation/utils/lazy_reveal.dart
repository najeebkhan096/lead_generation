import 'package:flutter/widgets.dart';

/// Reveals a long in-memory list a window at a time as you scroll.
///
/// For lists that are already fully in memory (a parsed Excel archive) but
/// whose cards are expensive to build all at once: render
/// `items.take(revealCount)`, attach [revealController] to the scrollable,
/// and the window grows by [revealStep] whenever the scroll position nears
/// the end. Call [resetReveal] when the filter changes.
mixin LazyRevealMixin<T extends StatefulWidget> on State<T> {
  static const revealStep = 40;

  final ScrollController revealController = ScrollController();
  int revealCount = revealStep;

  void initReveal() => revealController.addListener(_onRevealScroll);

  void disposeReveal() {
    revealController
      ..removeListener(_onRevealScroll)
      ..dispose();
  }

  void resetReveal() {
    if (revealCount != revealStep) setState(() => revealCount = revealStep);
  }

  void _onRevealScroll() {
    if (!revealController.hasClients) return;
    final position = revealController.position;
    if (position.maxScrollExtent - position.pixels < 700) {
      setState(() => revealCount += revealStep);
    }
  }
}
