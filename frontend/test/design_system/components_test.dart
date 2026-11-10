import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/presentation/design_system/design_system.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(body: Center(child: SizedBox(width: 420, child: child))),
    );

void main() {
  group('AppButton', () {
    testWidgets('fires onPressed; null disables; loading blocks and shows a spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppButton.primary(label: 'Save', onPressed: () => taps++)));
      await tester.tap(find.text('Save'));
      expect(taps, 1);

      await tester.pumpWidget(_host(const AppButton.primary(label: 'Save', onPressed: null)));
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(taps, 1);

      await tester.pumpWidget(_host(AppButton.primary(label: 'Save', loading: true, onPressed: () => taps++)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(taps, 1, reason: 'a loading button ignores presses');
    });

    testWidgets('every variant and size renders in both themes', (tester) async {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        for (final variant in AppButtonVariant.values) {
          for (final size in AppButtonSize.values) {
            await tester.pumpWidget(_host(
              AppButton(label: 'Go', icon: AppIcons.check, variant: variant, size: size, onPressed: () {}),
              theme: theme,
            ));
            expect(find.text('Go'), findsOneWidget, reason: '$variant/$size');
          }
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the primary button keeps a 40px target and the small one 32px', (tester) async {
      await tester.pumpWidget(_host(AppButton.primary(label: 'Go', onPressed: () {})));
      expect(tester.getSize(find.byType(FilledButton)).height, 40);
      await tester.pumpWidget(_host(AppButton.primary(label: 'Go', size: AppButtonSize.sm, onPressed: () {})));
      expect(tester.getSize(find.byType(FilledButton)).height, 32);
    });
  });

  group('AppDropdown / AppMultiSelect', () {
    testWidgets('opens, shows options, and reports the chosen value', (tester) async {
      String? chosen;
      await tester.pumpWidget(_host(AppDropdown<String>(
        label: 'Range',
        value: 'a',
        options: const [AppOption('a', 'Last 7 days'), AppOption('b', 'Last 30 days')],
        onChanged: (v) => chosen = v,
      )));
      expect(find.text('Range'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);

      await tester.tap(find.text('Last 7 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 30 days'));
      await tester.pumpAndSettle();
      expect(chosen, 'b');
    });

    testWidgets('a disabled dropdown does not open', (tester) async {
      await tester.pumpWidget(_host(const AppDropdown<String>(
        value: 'a',
        options: [AppOption('a', 'One'), AppOption('b', 'Two')],
        onChanged: null,
      )));
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      expect(find.text('Two'), findsNothing);
    });

    testWidgets('multi-select toggles options and keeps the menu open', (tester) async {
      var values = <String>{};
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => AppMultiSelect<String>(
          hint: 'Pick',
          values: values,
          options: const [AppOption('x', 'Texas'), AppOption('y', 'Ohio'), AppOption('z', 'Utah')],
          onChanged: (v) => setState(() => values = v),
        ),
      )));
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Texas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ohio'));
      await tester.pumpAndSettle();
      expect(values, {'x', 'y'});
      expect(find.text('Utah'), findsOneWidget, reason: 'the menu stayed open');

      await tester.tap(find.text('Texas'));
      await tester.pumpAndSettle();
      expect(values, {'y'});
    });
  });

  group('inputs', () {
    testWidgets('AppTextField shows its label, hint and validation message', (tester) async {
      await tester.pumpWidget(_host(const AppTextField(label: 'Name', hint: 'Jane', error: 'Required', required: true)));
      expect(find.textContaining('Name'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('AppSearchField reports typing and clears', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(_host(AppSearchField(hint: 'Search leads', onChanged: seen.add)));
      await tester.enterText(find.byType(TextField), 'plumber');
      expect(seen.last, 'plumber');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(seen.last, '');
    });

    testWidgets('AppCheckboxTile toggles from a tap on its label', (tester) async {
      var value = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => AppCheckboxTile(value: value, label: 'Remember me', onChanged: (v) => setState(() => value = v)),
      )));
      await tester.tap(find.text('Remember me'));
      expect(value, isTrue);
    });
  });

  group('display', () {
    testWidgets('AppBadge, StatCard and EmptyState render their content', (tester) async {
      await tester.pumpWidget(_host(const Column(children: [
        AppBadge('Active', tone: AppTone.success, dot: true),
        StatCard(label: 'Leads', value: '1,204', icon: AppIcons.leads, delta: '+12 this week'),
        EmptyState(icon: AppIcons.inbox, title: 'Nothing yet', message: 'Run a scan.'),
      ])));
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('1,204'), findsOneWidget);
      expect(find.text('+12 this week'), findsOneWidget);
      expect(find.text('Nothing yet'), findsOneWidget);
    });

    testWidgets('StatCard shows a skeleton instead of a number while loading', (tester) async {
      await tester.pumpWidget(_host(const SkeletonScope(child: StatCard(label: 'Leads', value: '99', icon: AppIcons.leads, loading: true))));
      expect(find.text('99'), findsNothing);
      expect(find.byType(Skeleton), findsOneWidget);
    });

    testWidgets('ShareBar lists each segment with its share', (tester) async {
      await tester.pumpWidget(_host(const ShareBar(segments: [
        ShareSegment(label: 'Review', value: 75, tone: AppTone.primary),
        ShareSegment(label: 'No website', value: 25, tone: AppTone.info),
      ])));
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
    });

    testWidgets('AppProgressBar animates to its value', (tester) async {
      await tester.pumpWidget(_host(const AppProgressBar(value: 0.5)));
      await tester.pumpAndSettle();
      final fill = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(fill.widthFactor, closeTo(0.5, 0.001));
    });

    test('number formatting', () {
      expect(groupedNumber(1234567), '1,234,567');
      expect(groupedNumber(12), '12');
      expect(compactNumber(950), '950');
      expect(compactNumber(1500), '1.5k');
      expect(compactNumber(24000), '24k');
    });

    testWidgets('AppAlert shows its title, message and actions', (tester) async {
      var clicked = false;
      await tester.pumpWidget(_host(AppAlert(
        tone: AppTone.warning,
        title: 'Paused',
        message: 'Google asked for a check.',
        actions: [AppButton.outlined(label: 'Retry', size: AppButtonSize.sm, onPressed: () => clicked = true)],
      )));
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(clicked, isTrue);
    });
  });

  group('dialogs', () {
    testWidgets('showConfirmDialog resolves true only when confirmed', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: AppButton.primary(
                label: 'Ask',
                onPressed: () async => result = await showConfirmDialog(context, title: 'Delete?', message: 'Gone for good.', confirmLabel: 'Delete', destructive: true),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  testWidgets('ResponsiveGrid never leaves an orphan tile when evenRows is on', (tester) async {
    Future<int> columnsAt(double width) async {
      tester.view.physicalSize = Size(width + 40, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: ResponsiveGrid(minTileWidth: 190, children: [for (var i = 0; i < 6; i++) Container(key: ValueKey(i), height: 20)]),
          ),
        ),
      ));
      final lefts = {for (var i = 0; i < 6; i++) tester.getTopLeft(find.byKey(ValueKey(i))).dx};
      return lefts.length;
    }

    addTearDown(tester.view.reset);
    expect(await columnsAt(1400), 6);
    expect(await columnsAt(1100), 3, reason: '5 would leave an orphan, so 3');
    expect(await columnsAt(500), 2);
    expect(await columnsAt(300), 1);
  });
}
