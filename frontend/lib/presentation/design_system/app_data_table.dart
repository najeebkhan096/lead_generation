import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One column of an [AppDataTable] / [SliverAppTable].
///
/// A column is either fixed ([width]) or flexible ([flex] > 0 shares what is
/// left). [minWidth] is the least a flexible column is allowed.
class AppColumn<T> {
  const AppColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 0,
    this.minWidth = 96,
    this.alignment = Alignment.centerLeft,
    this.sortable = false,
    this.priority = 0,
  });

  final String label;
  final Widget Function(BuildContext context, T row) cell;
  final double? width;
  final int flex;
  final double minWidth;
  final Alignment alignment;
  final bool sortable;

  /// `0` = always shown. When the table is too narrow, columns with the
  /// highest priority number are dropped first (ties: the right-most).
  final int priority;
}

const double _checkboxColumn = 48;
const double _rowHeight = 60;
const double _headerHeight = 40;
const double _cellPad = AppSpace.md;

class _Widths {
  _Widths(this.columns, this.available, this.selectable);

  final List<AppColumn<dynamic>> columns;
  final double available;
  final bool selectable;

  double get fixedTotal => columns.fold(0.0, (sum, c) => sum + (c.width ?? (c.flex > 0 ? c.minWidth : 0)));

  /// The least width the table can be laid out in without squeezing a column.
  double get minTotal => fixedTotal + (selectable ? _checkboxColumn : 0);

  late final List<double> widths = () {
    final extra = (available - minTotal).clamp(0.0, double.infinity);
    final flexTotal = columns.fold<int>(0, (sum, c) => sum + c.flex);
    return [
      for (final c in columns)
        c.width ?? (c.flex > 0 ? c.minWidth + (flexTotal == 0 ? 0 : extra * c.flex / flexTotal) : 0),
    ];
  }();
}

/// The least width, in logical pixels, a table needs even with every
/// droppable (priority > 0) column hidden.
double minTableWidth(List<AppColumn<dynamic>> columns, {bool selectable = false}) =>
    _Widths([for (final c in columns) if (c.priority == 0) c], 0, selectable).minTotal;

/// [columns] with the lowest-priority ones removed until the rest fit in
/// [available] (or only mandatory columns remain).
List<AppColumn<T>> fitColumns<T>(List<AppColumn<T>> columns, double available, {bool selectable = false}) {
  final kept = [...columns];
  while (_Widths(kept, 0, selectable).minTotal > available) {
    var worst = -1;
    for (var i = 0; i < kept.length; i++) {
      if (kept[i].priority > 0 && (worst == -1 || kept[i].priority >= kept[worst].priority)) worst = i;
    }
    if (worst == -1) break;
    kept.removeAt(worst);
  }
  return kept;
}

/// A data table for a bounded number of rows. It scrolls sideways when the
/// window is narrower than its columns need. For long, lazily-loaded lists use
/// [SliverAppTable].
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowKey,
    this.onRowTap,
    this.selected,
    this.onSelectionChanged,
    this.sortBy,
    this.sortAscending = true,
    this.onSort,
    this.empty,
  });

  final List<AppColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) rowKey;
  final void Function(T row)? onRowTap;

  /// Row selection: pass both to show checkboxes.
  final Set<String>? selected;
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// The label of the column the rows are sorted by.
  final String? sortBy;
  final bool sortAscending;
  final void Function(String column, bool ascending)? onSort;

  /// Shown instead of the rows when there are none.
  final Widget? empty;

  bool get _selectable => selected != null && onSelectionChanged != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _frame(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) {
          final columns = fitColumns(this.columns, c.maxWidth, selectable: _selectable);
          final layout = _Widths(columns, c.maxWidth, _selectable);
          final tableWidth = c.maxWidth < layout.minTotal ? layout.minTotal : c.maxWidth;
          final content = SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _HeaderRow<T>(
                  columns: columns,
                  widths: _Widths(columns, tableWidth, _selectable).widths,
                  selectable: _selectable,
                  allSelected: _selectable && rows.isNotEmpty && rows.every((r) => selected!.contains(rowKey(r))),
                  someSelected: _selectable && rows.any((r) => selected!.contains(rowKey(r))),
                  onToggleAll: _selectable ? (all) => onSelectionChanged!(all ? rows.map(rowKey).toSet() : <String>{}) : null,
                  sortBy: sortBy,
                  sortAscending: sortAscending,
                  onSort: onSort,
                  topRadius: false,
                ),
                if (rows.isEmpty && empty != null)
                  empty!
                else
                  for (var i = 0; i < rows.length; i++)
                    _DataRow<T>(
                      row: rows[i],
                      columns: columns,
                      widths: _Widths(columns, tableWidth, _selectable).widths,
                      selectable: _selectable,
                      selected: _selectable && selected!.contains(rowKey(rows[i])),
                      onSelect: _selectable
                          ? (on) {
                              final next = {...selected!};
                              on ? next.add(rowKey(rows[i])) : next.remove(rowKey(rows[i]));
                              onSelectionChanged!(next);
                            }
                          : null,
                      onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
                      last: i == rows.length - 1,
                      framed: false,
                    ),
              ],
            ),
          );
          if (c.maxWidth >= layout.minTotal) return content;
          return Scrollbar(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: content));
        },
      ),
    );
  }
}

BoxDecoration _frame() => BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: AppTheme.border),
      boxShadow: AppTheme.shadowCard,
    );

/// The same table as slivers, so only the rows near the screen are built —
/// a list of thousands costs what a list of fifty does. The caller supplies the
/// scroll view (and decides what to do when the window is narrower than
/// [minTableWidth]: a table that cannot fit should be a list of cards instead).
class SliverAppTable<T> extends StatelessWidget {
  const SliverAppTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowKey,
    this.onRowTap,
    this.selected,
    this.onSelectionChanged,
    this.sortBy,
    this.sortAscending = true,
    this.onSort,
  });

  final List<AppColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) rowKey;
  final void Function(T row)? onRowTap;
  final Set<String>? selected;
  final ValueChanged<Set<String>>? onSelectionChanged;
  final String? sortBy;
  final bool sortAscending;
  final void Function(String column, bool ascending)? onSort;

  bool get _selectable => selected != null && onSelectionChanged != null;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        // The rows draw a 1px frame on each side; the cells share what is inside it.
        final inner = constraints.crossAxisExtent - 2;
        final columns = fitColumns(this.columns, inner, selectable: _selectable);
        final widths = _Widths(columns, inner, _selectable).widths;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _HeaderRow<T>(
                columns: columns,
                widths: widths,
                selectable: _selectable,
                allSelected: _selectable && rows.isNotEmpty && rows.every((r) => selected!.contains(rowKey(r))),
                someSelected: _selectable && rows.any((r) => selected!.contains(rowKey(r))),
                onToggleAll: _selectable ? (all) => onSelectionChanged!(all ? rows.map(rowKey).toSet() : <String>{}) : null,
                sortBy: sortBy,
                sortAscending: sortAscending,
                onSort: onSort,
                topRadius: true,
              ),
            ),
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final key = rowKey(rows[i]);
                return _DataRow<T>(
                  row: rows[i],
                  columns: columns,
                  widths: widths,
                  selectable: _selectable,
                  selected: _selectable && selected!.contains(key),
                  onSelect: _selectable
                      ? (on) {
                          final next = {...selected!};
                          on ? next.add(key) : next.remove(key);
                          onSelectionChanged!(next);
                        }
                      : null,
                  onTap: onRowTap == null ? null : () => onRowTap!(rows[i]),
                  last: i == rows.length - 1,
                  framed: true,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.widths,
    required this.selectable,
    required this.allSelected,
    required this.someSelected,
    required this.onToggleAll,
    required this.sortBy,
    required this.sortAscending,
    required this.onSort,
    required this.topRadius,
  });

  final List<AppColumn<T>> columns;
  final List<double> widths;
  final bool selectable;
  final bool allSelected;
  final bool someSelected;
  final ValueChanged<bool>? onToggleAll;
  final String? sortBy;
  final bool sortAscending;
  final void Function(String column, bool ascending)? onSort;
  final bool topRadius;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(AppTheme.radiusCard);
    return Container(
      height: _headerHeight,
      decoration: BoxDecoration(
        color: AppTheme.isDark ? AppTheme.neutral100.withValues(alpha: 0.5) : AppTheme.background,
        borderRadius: topRadius ? BorderRadius.only(topLeft: radius, topRight: radius) : null,
        border: Border(
          top: topRadius ? BorderSide(color: AppTheme.border) : BorderSide.none,
          left: topRadius ? BorderSide(color: AppTheme.border) : BorderSide.none,
          right: topRadius ? BorderSide(color: AppTheme.border) : BorderSide.none,
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          if (selectable)
            SizedBox(
              width: _checkboxColumn,
              child: Center(
                child: Checkbox(
                  tristate: true,
                  value: allSelected ? true : (someSelected ? null : false),
                  onChanged: (_) => onToggleAll?.call(!allSelected),
                ),
              ),
            ),
          for (var i = 0; i < columns.length; i++)
            SizedBox(
              width: widths[i],
              child: _HeaderCell(
                label: columns[i].label,
                alignment: columns[i].alignment,
                sortable: columns[i].sortable && onSort != null,
                active: sortBy == columns[i].label,
                ascending: sortAscending,
                onTap: () => onSort?.call(columns[i].label, sortBy == columns[i].label ? !sortAscending : true),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.alignment,
    required this.sortable,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final Alignment alignment;
  final bool sortable;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppText.columnHeader.copyWith(color: active ? AppTheme.textPrimary : AppTheme.textMuted);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label.toUpperCase(), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (sortable) ...[
          const SizedBox(width: 4),
          Icon(
            active ? (ascending ? AppIcons.arrowUp : AppIcons.arrowDown) : AppIcons.arrowUpDown,
            size: 12,
            color: active ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.6),
          ),
        ],
      ],
    );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _cellPad),
      child: Align(alignment: alignment, child: content),
    );
    if (!sortable) return padded;
    return InkWell(onTap: onTap, child: padded);
  }
}

class _DataRow<T> extends StatefulWidget {
  const _DataRow({
    required this.row,
    required this.columns,
    required this.widths,
    required this.selectable,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.last,
    required this.framed,
  });

  final T row;
  final List<AppColumn<T>> columns;
  final List<double> widths;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onSelect;
  final VoidCallback? onTap;
  final bool last;

  /// Draw the left / right / bottom frame (sliver rows draw their own).
  final bool framed;

  @override
  State<_DataRow<T>> createState() => _DataRowState<T>();
}

class _DataRowState<T> extends State<_DataRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(AppTheme.radiusCard);
    final bg = widget.selected
        ? AppTheme.primary100.withValues(alpha: AppTheme.isDark ? 0.5 : 0.6)
        : (_hover ? AppTheme.neutral100.withValues(alpha: 0.6) : AppTheme.surface);
    final line = BorderSide(color: AppTheme.border);
    final row = Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: widget.framed && widget.last ? BorderRadius.only(bottomLeft: radius, bottomRight: radius) : null,
        border: Border(
          left: widget.framed ? line : BorderSide.none,
          right: widget.framed ? line : BorderSide.none,
          bottom: widget.last && !widget.framed ? BorderSide.none : line,
        ),
      ),
      child: Row(
        children: [
          if (widget.selectable)
            SizedBox(
              width: _checkboxColumn,
              child: Center(child: Checkbox(value: widget.selected, onChanged: (v) => widget.onSelect?.call(v ?? false))),
            ),
          for (var i = 0; i < widget.columns.length; i++)
            SizedBox(
              width: widget.widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _cellPad),
                child: Align(
                  alignment: widget.columns[i].alignment,
                  child: DefaultTextStyle.merge(
                    style: AppText.cell,
                    overflow: TextOverflow.ellipsis,
                    child: widget.columns[i].cell(context, widget.row),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: widget.onTap == null
          ? row
          : GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: row),
    );
  }
}
