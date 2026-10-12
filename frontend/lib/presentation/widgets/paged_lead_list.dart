import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The widest the content gets on a large window.
const _maxContentWidth = 1080.0;

/// How close to the end (in logical pixels) the list must be scrolled
/// before the next page is requested — far enough ahead that a page has
/// usually arrived before the user reaches the bottom.
const _loadAheadExtent = 900.0;

/// A scrolling page of cards that loads more as you reach the end.
///
/// The cards live in a [SliverGrid], so only the ones on (or near) the
/// screen are ever built — a list of thousands costs the same to render as a
/// list of fifty. [onLoadMore] fires when the scroll position nears the end
/// and again, if the content doesn't fill the window yet, until it does.
///
/// [header] (title, controls) scrolls with the list. [placeholder] replaces
/// the grid while there's nothing to show (first load, an error, no matches).
class PagedLeadList extends StatefulWidget {
  const PagedLeadList({
    super.key,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onRefresh,
    this.placeholder,
    this.mainAxisExtent = 248,
    this.maxCardWidth = 340,
  });

  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final Future<void> Function() onRefresh;
  final Widget? placeholder;
  final double mainAxisExtent;
  final double maxCardWidth;

  @override
  State<PagedLeadList> createState() => _PagedLeadListState();
}

class _PagedLeadListState extends State<PagedLeadList> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
    _scheduleFillCheck();
  }

  @override
  void didUpdateWidget(PagedLeadList old) {
    super.didUpdateWidget(old);
    // A new page may still not fill the window (tall monitor, short page).
    _scheduleFillCheck();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!widget.hasMore || widget.loadingMore || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.maxScrollExtent - position.pixels < _loadAheadExtent) {
      widget.onLoadMore();
    }
  }

  void _scheduleFillCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (!widget.hasMore || widget.loadingMore || widget.placeholder != null) return;
      // Not scrollable at all: the user can't scroll to trigger the next
      // page, so fetch it until the content overflows the window.
      if (_controller.position.maxScrollExtent <= 0 && widget.itemCount > 0) {
        widget.onLoadMore();
      }
    });
  }

  double _sidePadding(double width) => math.max(28, (width - _maxContentWidth) / 2);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final side = _sidePadding(constraints.crossAxisExtent);
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 28, side, 0),
                sliver: SliverToBoxAdapter(child: widget.header),
              );
            },
          ),
          if (widget.placeholder != null)
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final side = _sidePadding(constraints.crossAxisExtent);
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 16, side, 40),
                  sliver: SliverToBoxAdapter(child: widget.placeholder),
                );
              },
            )
          else ...[
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final side = _sidePadding(constraints.crossAxisExtent);
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 16, side, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: widget.maxCardWidth,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: widget.mainAxisExtent,
                    ),
                    itemCount: widget.itemCount,
                    itemBuilder: widget.itemBuilder,
                  ),
                );
              },
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final side = _sidePadding(constraints.crossAxisExtent);
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 20, side, 40),
                  sliver: SliverToBoxAdapter(child: _Footer(
                    loadingMore: widget.loadingMore,
                    hasMore: widget.hasMore,
                    count: widget.itemCount,
                    onLoadMore: widget.onLoadMore,
                  )),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loadingMore,
    required this.hasMore,
    required this.count,
    required this.onLoadMore,
  });

  final bool loadingMore;
  final bool hasMore;
  final int count;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
      return const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (hasMore) {
      // Scrolling loads the next page on its own; the button is the
      // fallback for a window where scroll can't reach the trigger.
      return Center(
        child: OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(AppIcons.chevronDown, size: 18),
          label: const Text('Load more'),
        ),
      );
    }
    return Center(
      child: Text(
        'Showing all $count',
        style: const TextStyle(fontSize: 12.5, color: AppTheme.faint, fontWeight: FontWeight.w600),
      ),
    );
  }
}
