import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/coverage_option.dart';
import 'package:lead_generation_app/domain/entities/maps_session_status.dart';
import 'package:lead_generation_app/domain/entities/scan_run.dart';
import 'package:lead_generation_app/domain/entities/state_city_scan_snapshot.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/excel_scan_page.dart';
import 'package:lead_generation_app/presentation/pages/state_scan_page.dart';

class _Repo implements LeadRepository {
  _Repo({
    this.session = const MapsSessionStatus(status: 'signed_in', ready: true),
    List<ScanRun>? runs,
    this.status = const StateCityScanSnapshot(active: false, status: 'idle'),
    this.resumeFails,
  }) : runs = runs ?? [];

  MapsSessionStatus session;
  final List<ScanRun> runs;
  StateCityScanSnapshot status;
  final String? resumeFails;
  final starts = <Map<String, Object?>>[];
  final resumed = <String>[];
  final discarded = <String>[];

  @override
  Future<List<ScanRun>> listNoWebsiteRuns() async => [...runs];

  @override
  Future<void> resumeNoWebsiteRun(String id) async {
    if (resumeFails != null) throw Exception(resumeFails);
    resumed.add(id);
  }

  @override
  Future<void> discardNoWebsiteRun(String id) async {
    discarded.add(id);
    runs.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<CoverageOption>> getScanCoverage() async => const [];

  @override
  Future<StateCityScanSnapshot> getStateScanStatus() async => status;

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

Future<_Repo> _pump(WidgetTester tester, {String path = '/scan', _Repo? repo, Widget Function()? progress}) async {
  tester.view.physicalSize = const Size(1500, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = repo ?? _Repo();
  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(path: '/scan', builder: (context, state) => ExcelScanPage(type: state.uri.queryParameters['type'])),
      GoRoute(path: '/scan-progress', builder: (context, state) => progress?.call() ?? const Scaffold(body: Text('PROGRESS PAGE'))),
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

  group('resuming a no-website scan', () {
    const stopped = ScanRun(
      id: 'run-1',
      categories: ['Plumber', 'Dentist'],
      status: 'stopped',
      citiesTotal: 400,
      citiesDone: 100,
      leads: 37,
      businesses: 900,
      percent: 25,
    );
    const interrupted = ScanRun(id: 'run-2', categories: ['Barber shop'], status: 'interrupted', citiesTotal: 50, citiesDone: 10, leads: 3, percent: 20);

    testWidgets('unfinished no-website scans are listed with their progress', (tester) async {
      await _pump(tester, path: '/scan?type=no-website', repo: _Repo(runs: [stopped, interrupted]));
      expect(find.text('Unfinished no-website scans'), findsOneWidget);
      expect(find.text('Plumber, Dentist'), findsOneWidget);
      expect(find.textContaining('25% done · 37 no-website leads · 300 cities left'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Interrupted'), findsOneWidget, reason: 'a scan cut off by a restart says so');
      expect(find.text('Resume'), findsNWidgets(2));
    });

    testWidgets('nothing is listed for the 1-star scan, or when there is nothing to resume', (tester) async {
      await _pump(tester, repo: _Repo(runs: [stopped]));
      expect(find.text('Unfinished no-website scans'), findsNothing, reason: '1-star scans resume from the Archive');

      await _pump(tester, path: '/scan?type=no-website', repo: _Repo());
      expect(find.text('Unfinished no-website scans'), findsNothing);
    });

    testWidgets('Resume asks the backend to resume that scan and opens the live progress', (tester) async {
      final repo = await _pump(tester, path: '/scan?type=no-website', repo: _Repo(runs: [stopped, interrupted]));
      await tester.tap(find.text('Resume').first);
      await tester.pumpAndSettle();
      expect(repo.resumed, ['run-1']);
      expect(find.text('PROGRESS PAGE'), findsOneWidget);
    });

    testWidgets('a refused resume is explained and stays on the page', (tester) async {
      final repo = await _pump(tester, path: '/scan?type=no-website', repo: _Repo(runs: [stopped], resumeFails: 'Every city was already covered.'));
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(repo.resumed, isEmpty);
      expect(find.text('Every city was already covered.'), findsOneWidget);
      expect(find.text('PROGRESS PAGE'), findsNothing);
    });

    testWidgets('while another scan is running nothing can be resumed', (tester) async {
      final running = StateCityScanSnapshot.fromJson({'status': 'running', 'active': true, 'currentCategory': 'Plumber'});
      final repo = await _pump(tester, path: '/scan?type=no-website', repo: _Repo(runs: [stopped], status: running));
      await tester.tap(find.text('Resume'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.resumed, isEmpty);
    });

    testWidgets('Discard asks first, then forgets the scan and refreshes the list', (tester) async {
      final repo = await _pump(tester, path: '/scan?type=no-website', repo: _Repo(runs: [stopped]));
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this scan?'), findsOneWidget);
      expect(find.textContaining('37 no-website leads already found stay'), findsOneWidget, reason: 'discarding never deletes leads');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.discarded, isEmpty);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(repo.discarded, ['run-1']);
      expect(find.text('Unfinished no-website scans'), findsNothing);
    });

    testWidgets('a scan stopped after the page opened appears on its own, without a reload', (tester) async {
      final repo = await _pump(tester, path: '/scan?type=no-website', repo: _Repo());
      expect(find.text('Unfinished no-website scans'), findsNothing);

      repo.runs.add(stopped); // e.g. the scan was just stopped, or the backend restarted
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text('Unfinished no-website scans'), findsOneWidget);
      expect(find.text('Plumber, Dentist'), findsOneWidget);
    });

    testWidgets('choosing the no-website type refreshes the list straight away', (tester) async {
      final repo = await _pump(tester, repo: _Repo());
      repo.runs.add(stopped);
      await tester.tap(find.text('No website').first);
      await tester.pumpAndSettle();
      expect(find.text('Unfinished no-website scans'), findsOneWidget);
    });

    test('ScanRun parses the backend payload', () {
      final run = ScanRun.fromJson({
        'id': 'r',
        'categories': ['A'],
        'status': 'interrupted',
        'startedAt': 1800000000000,
        'updatedAt': 1800000100000,
        'citiesTotal': 10,
        'citiesDone': 4,
        'leads': 2,
        'percent': 40,
      });
      expect(run.interrupted, isTrue);
      expect(run.citiesLeft, 6);
      expect(run.updatedAt, DateTime.fromMillisecondsSinceEpoch(1800000100000));
    });

    Map<String, dynamic> snapshot({required String mode, required bool cancelled, String status = 'done', String? runId = 'run-9'}) => {
          'status': status,
          'active': status == 'running',
          'mode': mode,
          'cancelled': cancelled,
          'runId': runId,
          'startedAt': 1800000000000,
          'categories': [
            {'category': 'Plumber', 'status': 'cancelled', 'statesTotal': 1, 'statesDone': 0, 'citiesTotal': 4, 'citiesDone': 2, 'archive': {'status': 'failed', 'error': 'n/a'}, 'states': []},
          ],
        };

    test('only a stopped no-website scan can be resumed from the progress page', () {
      expect(StateCityScanSnapshot.fromJson(snapshot(mode: 'no_website', cancelled: true)).canResume, isTrue);
      expect(StateCityScanSnapshot.fromJson(snapshot(mode: 'no_website', cancelled: false)).canResume, isFalse, reason: 'it finished');
      expect(StateCityScanSnapshot.fromJson(snapshot(mode: 'no_website', cancelled: true, status: 'running')).canResume, isFalse);
      expect(StateCityScanSnapshot.fromJson(snapshot(mode: 'reviews', cancelled: true)).canResume, isFalse, reason: '1-star resumes from the Archive');
      expect(StateCityScanSnapshot.fromJson(snapshot(mode: 'no_website', cancelled: true, runId: null)).canResume, isFalse);
    });

    testWidgets('the progress page of a stopped no-website scan offers Resume scan', (tester) async {
      final repo = _Repo(status: StateCityScanSnapshot.fromJson(snapshot(mode: 'no_website', cancelled: true)));
      await _pump(tester, path: '/scan-progress', repo: repo, progress: () => const StateScanPage());
      expect(find.text('No-website scan progress'), findsOneWidget);
      expect(find.textContaining('Stopped — resume to carry on'), findsOneWidget);
      await tester.tap(find.text('Resume scan'));
      await tester.pump();
      expect(repo.resumed, ['run-9']);
    });

    testWidgets('a finished scan, or a 1-star one, shows no Resume scan button', (tester) async {
      final finished = _Repo(status: StateCityScanSnapshot.fromJson(snapshot(mode: 'no_website', cancelled: false)));
      await _pump(tester, path: '/scan-progress', repo: finished, progress: () => const StateScanPage());
      expect(find.text('Resume scan'), findsNothing);

      final oneStar = _Repo(status: StateCityScanSnapshot.fromJson(snapshot(mode: 'reviews', cancelled: true)));
      await _pump(tester, path: '/scan-progress', repo: oneStar, progress: () => const StateScanPage());
      expect(find.text('Resume scan'), findsNothing);
    });
  });

  test('the snapshot knows which kind of scan it is', () {
    expect(StateCityScanSnapshot.fromJson({'status': 'running', 'mode': 'no_website'}).isNoWebsite, isTrue);
    expect(StateCityScanSnapshot.fromJson({'status': 'running', 'mode': 'reviews'}).isNoWebsite, isFalse);
    expect(StateCityScanSnapshot.fromJson({'status': 'running'}).isNoWebsite, isFalse, reason: 'older backends say nothing: 1-star');
  });
}
