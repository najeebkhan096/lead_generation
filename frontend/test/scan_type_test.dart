import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/coverage_option.dart';
import 'package:lead_generation_app/domain/entities/maps_session_status.dart';
import 'package:lead_generation_app/domain/entities/state_city_scan_snapshot.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/excel_scan_page.dart';

class _Repo implements LeadRepository {
  _Repo({this.session = const MapsSessionStatus(status: 'signed_in', ready: true)});

  MapsSessionStatus session;
  final starts = <Map<String, Object?>>[];

  @override
  Future<List<CoverageOption>> getScanCoverage() async => const [];

  @override
  Future<StateCityScanSnapshot> getStateScanStatus() async => const StateCityScanSnapshot(active: false, status: 'idle');

  @override
  Future<MapsSessionStatus> getMapsSessionStatus({bool refresh = false}) async => session;

  @override
  Future<void> startStateScan({
    required List<String> categories,
    int concurrency = 5,
    String dateRange = '30',
    int maxResultsPerCity = 160,
    bool analyze = false,
    String coverage = 'standard',
    String mode = 'reviews',
  }) async =>
      starts.add({'categories': categories, 'dateRange': dateRange, 'coverage': coverage, 'mode': mode});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Repo> _pump(WidgetTester tester, {String path = '/scan', _Repo? repo}) async {
  tester.view.physicalSize = const Size(1500, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Repo();
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(path: '/scan', builder: (context, state) => ExcelScanPage(type: state.uri.queryParameters['type'])),
      GoRoute(path: '/scan-progress', builder: (context, state) => const Scaffold(body: Text('PROGRESS PAGE'))),
    ],
  );
  await tester.pumpWidget(RepositoryProvider<LeadRepository>.value(
    value: r,
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return r;
}

Future<void> _addCategory(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextFormField).first, name);
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the page asks what you are looking for, and 1-star is the default', (tester) async {
    await _pump(tester);
    expect(find.text('What are you looking for?'), findsOneWidget);
    expect(find.text('1-star reviews'), findsNWidgets(2), reason: 'the option and the summary');
    expect(find.text('No website'), findsOneWidget);
    // 1-star needs a time range (the field and its summary row).
    expect(find.text('Date range'), findsNWidgets(2));
    expect(find.text('Start 1-star scan'), findsOneWidget);
  });

  testWidgets('choosing "No website" removes the time range and the Google sign-in', (tester) async {
    await _pump(tester);
    expect(find.text('Date range'), findsNWidgets(2));

    await tester.tap(find.text('No website').first);
    await tester.pumpAndSettle();

    expect(find.text('Date range'), findsNothing, reason: 'no time range for a no-website scan');
    expect(find.text('Start no-website scan'), findsOneWidget);
    expect(find.text('Looking for'), findsOneWidget);
    expect(find.textContaining('Saved to No Website Leads'), findsWidgets);
  });

  testWidgets('the sidebar link opens the page already on the no-website type', (tester) async {
    await _pump(tester, path: '/scan?type=no-website');
    expect(find.text('Date range'), findsNothing);
    expect(find.text('Start no-website scan'), findsOneWidget);
  });

  testWidgets('a no-website scan is started with mode no_website, even when Google is signed out', (tester) async {
    final repo = _Repo(session: const MapsSessionStatus(status: 'signed_out'));
    await _pump(tester, path: '/scan?type=no-website', repo: repo);
    await _addCategory(tester, 'Plumber');

    await tester.tap(find.text('Start no-website scan'));
    await tester.pumpAndSettle();

    expect(repo.starts, hasLength(1));
    expect(repo.starts.single['mode'], 'no_website');
    expect(repo.starts.single['categories'], ['Plumber']);
    expect(find.text('PROGRESS PAGE'), findsOneWidget, reason: 'goes to the live progress');
  });

  testWidgets('a 1-star scan is still blocked while Google is signed out, and starts with its date range when signed in', (tester) async {
    final blocked = _Repo(session: const MapsSessionStatus(status: 'signed_out'));
    await _pump(tester, repo: blocked);
    await _addCategory(tester, 'Dentist');
    expect(find.text('Sign in to Google to start'), findsOneWidget);
    expect(blocked.starts, isEmpty);

    final ok = _Repo();
    await _pump(tester, repo: ok);
    await _addCategory(tester, 'Dentist');
    await tester.tap(find.text('Start 1-star scan'));
    await tester.pumpAndSettle();
    expect(ok.starts.single['mode'], 'reviews');
    expect(ok.starts.single['dateRange'], '30');
  });

  testWidgets('switching type back restores the time range', (tester) async {
    await _pump(tester, path: '/scan?type=no-website');
    await tester.tap(find.text('1-star reviews').first);
    await tester.pumpAndSettle();
    expect(find.text('Date range'), findsNWidgets(2));
  });

  test('the snapshot knows which kind of scan it is', () {
    expect(StateCityScanSnapshot.fromJson({'status': 'running', 'mode': 'no_website'}).isNoWebsite, isTrue);
    expect(StateCityScanSnapshot.fromJson({'status': 'running', 'mode': 'reviews'}).isNoWebsite, isFalse);
    expect(StateCityScanSnapshot.fromJson({'status': 'running'}).isNoWebsite, isFalse, reason: 'older backends say nothing: 1-star');
  });
}
