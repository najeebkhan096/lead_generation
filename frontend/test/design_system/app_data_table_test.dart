import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/presentation/design_system/design_system.dart';

class _Row {
  const _Row(this.id, this.name, this.score);

  final String id;
  final String name;
  final int score;
}

List<AppColumn<_Row>> _columns() => [
      AppColumn<_Row>(label: 'Name', flex: 2, minWidth: 200, sortable: true, cell: (c, r) => Text(r.name)),
      AppColumn<_Row>(label: 'Score', width: 100, sortable: true, cell: (c, r) => Text('${r.score}')),
      AppColumn<_Row>(label: 'Notes', width: 300, priority: 1, cell: (c, r) => Text('notes ${r.id}')),
      AppColumn<_Row>(label: 'Added', width: 200, priority: 2, cell: (c, r) => Text('added ${r.id}')),
    ];

const _rows = [_Row('a', 'Alpha', 3), _Row('b', 'Beta', 1), _Row('c', 'Gamma', 2)];

Widget _host(Widget child, {double width = 1000}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    );

void main() {
  group('fitColumns', () {
    test('keeps everything when it fits', () {
      expect(fitColumns(_columns(), 2000).map((c) => c.label), ['Name', 'Score', 'Notes', 'Added']);
    });

    test('drops the highest priority number first', () {
      // Name 200 + Score 100 + Notes 300 + Added 200 = 800; below that "Added" goes first.
      expect(fitColumns(_columns(), 700).map((c) => c.label), ['Name', 'Score', 'Notes']);
      expect(fitColumns(_columns(), 400).map((c) => c.label), ['Name', 'Score']);
    });

    test('never drops a mandatory column, however narrow', () {
      expect(fitColumns(_columns(), 10).map((c) => c.label), ['Name', 'Score']);
    });

    test('selection adds its checkbox column to the minimum width', () {
      expect(minTableWidth(_columns(), selectable: true), minTableWidth(_columns()) + 48);
      expect(minTableWidth(_columns()), 300); // mandatory columns only
    });
  });

  testWidgets('renders header, rows and hides optional columns on a narrow window', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(AppDataTable<_Row>(columns: _columns(), rows: _rows, rowKey: (r) => r.id), width: 500));
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('NOTES'), findsNothing, reason: 'dropped to fit 500px');
    expect(find.text('ADDED'), findsNothing);

    await tester.pumpWidget(_host(AppDataTable<_Row>(columns: _columns(), rows: _rows, rowKey: (r) => r.id), width: 1000));
    await tester.pump();
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('ADDED'), findsOneWidget);
  });

  testWidgets('tapping a sortable header reports the column and flips direction', (tester) async {
    final calls = <(String, bool)>[];
    String? sortBy;
    var asc = true;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => AppDataTable<_Row>(
        columns: _columns(),
        rows: _rows,
        rowKey: (r) => r.id,
        sortBy: sortBy,
        sortAscending: asc,
        onSort: (column, ascending) {
          calls.add((column, ascending));
          setState(() {
            sortBy = column;
            asc = ascending;
          });
        },
      ),
    )));

    await tester.tap(find.text('SCORE'));
    await tester.pump();
    await tester.tap(find.text('SCORE'));
    await tester.pump();
    await tester.tap(find.text('NOTES'), warnIfMissed: false); // not sortable
    expect(calls, [('Score', true), ('Score', false)]);
  });

  testWidgets('row selection: single, all, and none', (tester) async {
    var selected = <String>{};
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => AppDataTable<_Row>(
        columns: _columns(),
        rows: _rows,
        rowKey: (r) => r.id,
        selected: selected,
        onSelectionChanged: (next) => setState(() => selected = next),
      ),
    )));

    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(4)); // header + 3 rows

    await tester.tap(boxes.at(2));
    await tester.pump();
    expect(selected, {'b'});

    await tester.tap(boxes.first); // header: select all
    await tester.pump();
    expect(selected, {'a', 'b', 'c'});

    await tester.tap(boxes.first); // header again: clear
    await tester.pump();
    expect(selected, isEmpty);
  });

  testWidgets('a row tap fires onRowTap', (tester) async {
    _Row? tapped;
    await tester.pumpWidget(_host(AppDataTable<_Row>(columns: _columns(), rows: _rows, rowKey: (r) => r.id, onRowTap: (r) => tapped = r)));
    await tester.tap(find.text('Beta'));
    expect(tapped?.id, 'b');
  });

  testWidgets('the sliver table builds only the rows near the screen', (tester) async {
    final many = [for (var i = 0; i < 2000; i++) _Row('$i', 'Row $i', i)];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: CustomScrollView(slivers: [SliverAppTable<_Row>(columns: _columns(), rows: many, rowKey: (r) => r.id)]),
      ),
    ));
    expect(find.text('Row 0'), findsOneWidget);
    expect(find.text('Row 1999'), findsNothing, reason: 'off-screen rows are not built');
    expect(find.textContaining('Row ').evaluate().length, lessThan(30));
  });

  testWidgets('works in dark mode too', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: AppDataTable<_Row>(columns: _columns(), rows: _rows, rowKey: (r) => r.id)),
    ));
    expect(tester.takeException(), isNull);
  });
}
