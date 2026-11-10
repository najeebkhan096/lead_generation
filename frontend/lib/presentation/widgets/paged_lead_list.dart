import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_system/design_system.dart';

/// How close to the end (in logical pixels) the list must be scrolled
/// before the next page is requested — far enough ahead that a page has
/// usually arrived before the user reaches the bottom.
const _loadAheadExtent = 900.0;

/// A scrolling page of leads that loads more as you reach the end — as a
/// table when it fits the window, as cards when it does not.
///
/// Rows and cards live in slivers, so only the ones on (or near) the screen
/// are ever built — a list of thousands costs the same to render as a list of
/// fifty. [onLoadMore] fires when the scroll position nears the end and again,
/// if the content doesn't fill the window yet, until it does.
///
/// [header] (title, controls) scrolls with the list. [placeholder] replaces
/// the list while there's nothing to show (first load, an error, no matches).
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
    this.tableBuilder,
    this.tableMinWidth = 0,
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

  /// A sliver table to show instead of the cards when the content area is at
  /// least [tableMinWidth] wide. `null` always shows cards.
  final Widget Function(BuildContext context)? tableBuilder;
  final double tableMinWidth;

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

  /// The gutter on each side, so content is at most [AppSpace.pageMaxWidth] and centered.
  double _side(double width) => math.max(AppSpace.pageGutter(width), (width - AppSpace.pageMaxWidth) / 2);

  Widget _padded(double extent, {double top = 0, double bottom = 0, required Widget sliver}) {
    final side = _side(extent);
    return SliverPadding(padding: EdgeInsets.fromLTRB(side, top, side, bottom), sliver: sliver);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverLayoutBuilder(
            builder: (context, c) => _padded(
              c.crossAxisExtent,
              top: AppSpace.pageGutter(c.crossAxisExtent),
              sliver: SliverToBoxAdapter(child: widget.header),
            ),
          ),
          if (widget.placeholder != null)
            SliverLayoutBuilder(
              builder: (context, c) => _padded(
                c.crossAxisExtent,
                top: AppSpace.lg,
                bottom: AppSpace.xxxl,
                sliver: SliverToBoxAdapter(child: widget.placeholder),
              ),
            )
          else ...[
            SliverLayoutBuilder(
              builder: (context, c) {
                final side = _side(c.crossAxisExtent);
                final useTable = widget.tableBuilder != null && c.crossAxisExtent - side * 2 >= widget.tableMinWidth;
                return _padded(
                  c.crossAxisExtent,
                  top: AppSpace.lg,
                  sliver: useTable
                      ? widget.tableBuilder!(context)
                      : SliverGrid.builder(
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: c.crossAxisExtent - side * 2 < 700 ? double.infinity : widget.maxCardWidth,
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
              builder: (context, c) => _padded(
                c.crossAxisExtent,
                top: AppSpace.xl,
                bottom: AppSpace.xxxl,
                sliver: SliverToBoxAdapter(
                  child: _Footer(
                    loadingMore: widget.loadingMore,
                    hasMore: widget.hasMore,
                    count: widget.itemCount,
                    onLoadMore: widget.onLoadMore,
                  ),
                ),
              ),
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
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (hasMore) {
      // Scrolling loads the next page on its own; the button is the
      // fallback for a window where scroll can't reach the trigger.
      return Center(child: AppButton.outlined(label: 'Load more', icon: AppIcons.chevronDown, onPressed: onLoadMore));
    }
    return Center(child: Text('Showing all ${groupedNumber(count)}', style: Theme.of(context).textTheme.bodySmall));
  }
}
