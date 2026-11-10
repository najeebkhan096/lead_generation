import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/core/router/app_router.dart';
import 'package:lead_generation_app/core/theme/app_theme.dart';
import 'package:lead_generation_app/domain/entities/job.dart';
import 'package:lead_generation_app/domain/entities/job_filters.dart';
import 'package:lead_generation_app/domain/entities/job_scan.dart';
import 'package:lead_generation_app/domain/repositories/jobs_repository.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/explorer/jobs_explorer_bloc.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/explorer/jobs_explorer_event.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/jobs_overview_cubit.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/jobs_search_cubit.dart';
import 'package:lead_generation_app/presentation/pages/jobs/jobs_explorer_tab.dart';
import 'package:lead_generation_app/presentation/pages/jobs/jobs_hub_page.dart';
import 'package:lead_generation_app/presentation/pages/jobs/jobs_location_picker.dart';
import 'package:lead_generation_app/presentation/widgets/jobs/job_card.dart';
import 'package:lead_generation_app/presentation/widgets/jobs/jobs_ui.dart';
import 'package:lead_generation_app/presentation/widgets/jobs/scan_card.dart';

import 'support/fake_jobs_repository.dart';

class _NoLeads implements LeadRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

void _size(WidgetTester tester, double w, [double h = 1000]) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Job _fullJob({Map<String, dynamic> extra = const {}}) => fakeJob('1', title: 'Senior Flutter Developer with a very long title that has to wrap across more than one line on a phone', extra: {
      'companyName': 'Acme International Holdings Limited',
      'salaryMin': 120000, 'salaryMax': 150000, 'salaryCurrency': 'USD', 'salaryPeriod': 'year',
      'workArrangement': 'hybrid', 'employmentType': 'full_time', 'experienceLevel': 'senior', 'experienceYearsMin': 5,
      'postedAt': '2026-11-03T00:00:00Z',
      'requiredSkills': ['Flutter', 'Dart', 'Firebase', 'GraphQL', 'Kotlin', 'Swift', 'Docker', 'AWS'],
      'sourceNames': ['greenhouse', 'adzuna'],
      'applyUrl': 'https://careers.acme.test/1',
      ...extra,
    });

void main() {
  group('JobCard', () {
    Future<void> pumpCard(WidgetTester tester, Job job, {double width = 900, bool selected = false, void Function(JobTriage)? onTriage, VoidCallback? onOpen, VoidCallback? onToggle}) async {
      _size(tester, width + 40);
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: JobCard(job: job, selected: selected, busy: false, onToggleSelect: onToggle ?? () {}, onOpen: onOpen ?? () {}, onTriage: onTriage ?? (_) {}),
        ),
      )));
    }

    testWidgets('shows what a person scans for, and only what is known', (tester) async {
      await pumpCard(tester, _fullJob());
      expect(find.textContaining('Senior Flutter Developer with a very long title'), findsOneWidget);
      expect(find.text('Acme International Holdings Limited'), findsOneWidget);
      expect(find.text('Los Angeles, California, United States'), findsOneWidget);
      expect(find.text('USD 120,000 – 150,000 / year'), findsOneWidget);
      expect(find.text('Hybrid'), findsOneWidget);
      expect(find.text('Full time'), findsOneWidget);
      expect(find.text('Senior · 5+ years'), findsOneWidget);
      expect(find.textContaining('Posted Nov 3, 2026'), findsOneWidget);
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget, reason: 'six skills shown, the rest counted');
      expect(find.textContaining('via Greenhouse, Adzuna'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('a bare job shows no salary, no apply link and no invented pills', (tester) async {
      await pumpCard(tester, Job.fromJson({'id': 'b', 'title': 'Barista', 'companyName': 'Cafe'}));
      expect(find.text('Barista'), findsOneWidget);
      expect(find.text('Location not stated'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      expect(find.text('Original'), findsNothing);
      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining('Posted'), findsNothing);
    });

    testWidgets('fits a phone and a desktop without overflowing', (tester) async {
      for (final w in [340.0, 480.0, 1100.0]) {
        await pumpCard(tester, _fullJob(), width: w);
        expect(tester.takeException(), isNull, reason: 'width $w');
      }
    });

    testWidgets('actions: open, select, save, and the more-menu', (tester) async {
      final triage = <JobTriage>[];
      var opened = 0;
      var toggled = 0;
      await pumpCard(tester, _fullJob(), onTriage: triage.add, onOpen: () => opened++, onToggle: () => toggled++);
      await tester.tap(find.text('Details'));
      await tester.tap(find.byType(Checkbox));
      await tester.tap(find.text('Save'));
      expect([opened, toggled, triage], [1, 1, [JobTriage.save]]);

      await tester.tap(find.byIcon(AppIcons.more));
      await tester.pumpAndSettle();
      for (final item in ['Mark as applied', 'Mark as rejected', 'Mark as expired', 'Delete…']) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      expect(find.text('Remove from tracker'), findsNothing, reason: 'not tracked yet');
      await tester.tap(find.text('Mark as expired'));
      await tester.pumpAndSettle();
      expect(triage.last, JobTriage.expired);
    });

    testWidgets('a saved, expired job shows its state and offers to reactivate', (tester) async {
      final triage = <JobTriage>[];
      await pumpCard(tester, _fullJob(extra: {'userState': 'saved', 'applicationStage': 'saved', 'status': 'expired'}), onTriage: triage.add);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Save'), findsNothing, reason: 'already saved / closed');
      await tester.tap(find.byIcon(AppIcons.more));
      await tester.pumpAndSettle();
      expect(find.text('Mark as active again'), findsOneWidget);
      expect(find.text('Remove from tracker'), findsOneWidget);
      expect(find.text('Mark as expired'), findsNothing);
    });
  });

  group('ScanCard', () {
    testWidgets('live progress, what is being searched, the counters and the controls', (tester) async {
      _size(tester, 900);
      final calls = <String>[];
      await tester.pumpWidget(_app(SingleChildScrollView(
        child: ScanCard(
          scan: JobScan.fromJson(scanJson('r1', done: 4, total: 10)),
          expanded: true,
          onPause: () => calls.add('pause'),
          onStop: () => calls.add('stop'),
        ),
      )));
      expect(find.text('Flutter in CA'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.textContaining('4 of 10 searches · 40%'), findsOneWidget);
      expect(find.textContaining('United States › California › Los Angeles · Flutter Developer'), findsOneWidget);
      expect(find.text('15 new'), findsWidgets, reason: 'the scan total and the source row');
      expect(find.text('3 duplicates'), findsOneWidget);
      expect(find.text('Greenhouse'), findsOneWidget);
      expect(find.text('Not configured'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.tap(find.text('Stop'));
      expect(calls, ['pause', 'stop']);
    });

    testWidgets('a paused scan offers Resume; a finished one offers nothing', (tester) async {
      _size(tester, 900);
      await tester.pumpWidget(_app(ScanCard(scan: JobScan.fromJson(scanJson('r1', status: 'paused')), onResume: () {})));
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      await tester.pumpWidget(_app(ScanCard(scan: JobScan.fromJson(scanJson('r1', status: 'completed', done: 10)))));
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Stop'), findsNothing);
    });
  });

  group('Country → State → City picker', () {
    testWidgets('add a country, choose states, then specific cities; each choice reaches the draft', (tester) async {
      _size(tester, 1000, 1400);
      final repo = FakeJobsRepository();
      final cubit = JobsSearchCubit(repo, estimateDelay: const Duration(milliseconds: 5));
      addTearDown(cubit.close);
      await cubit.load();
      await tester.pumpWidget(_app(BlocProvider.value(
        value: cubit,
        child: BlocBuilder<JobsSearchCubit, JobsSearchState>(builder: (context, s) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: JobsLocationPicker(state: s))),
      )));

      await tester.tap(find.text('Add a country'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('United States').last);
      await tester.pumpAndSettle();
      expect(cubit.state.draft.countries.single.code, 'US');
      expect(find.text('All 3 states'), findsOneWidget);

      await tester.tap(find.textContaining('Choose states'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'California'));
      await tester.tap(find.widgetWithText(FilterChip, 'Texas'));
      await tester.pumpAndSettle();
      expect(cubit.state.draft.countries.single.regions, ['California', 'Texas']);

      await tester.tap(find.text('Each city'));
      await tester.pumpAndSettle();
      expect(find.text('All cities in the selected states'), findsOneWidget);
      await tester.tap(find.textContaining('Choose cities'));
      await tester.pumpAndSettle();
      expect(find.text('California'), findsWidgets);
      expect(find.text('0 of 3 cities'), findsOneWidget);

      await tester.tap(find.text('California').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Los Angeles'));
      await tester.pumpAndSettle();
      expect(cubit.state.draft.countries.single.cities.map((c) => c.city), ['Los Angeles']);
      expect(find.text('1 of 3 cities'), findsOneWidget);
      await tester.tap(find.text('Select all').last);
      await tester.pumpAndSettle();
      expect(cubit.state.draft.countries.single.cities, hasLength(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('worldwide has nothing to choose, and remote search is a switch on real countries', (tester) async {
      _size(tester, 1000, 1200);
      final repo = FakeJobsRepository();
      final cubit = JobsSearchCubit(repo, estimateDelay: const Duration(milliseconds: 5));
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.addCountry(repo.countriesData[2]);
      await cubit.addCountry(repo.countriesData[1]);
      await tester.pumpWidget(_app(BlocProvider.value(
        value: cubit,
        child: BlocBuilder<JobsSearchCubit, JobsSearchState>(builder: (context, s) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: JobsLocationPicker(state: s))),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Remote jobs that are open to people anywhere'), findsOneWidget);
      expect(find.textContaining('Also search remote jobs open in Qatar'), findsOneWidget);
      expect(find.text('Each municipality'), findsOneWidget, reason: 'Qatar calls its regions municipalities');
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(cubit.state.draft.countries.last.includeRemote, isTrue);
    });
  });

  group('Jobs explorer', () {
    Future<(FakeJobsRepository, JobsExplorerBloc)> pumpExplorer(WidgetTester tester, {List<Job>? jobs}) async {
      _size(tester, 1200, 1400);
      final repo = FakeJobsRepository(jobs: jobs ?? [fakeJob('1'), fakeJob('2', extra: {'city': 'Houston', 'state': 'Texas'}), fakeJob('3')]);
      final bloc = JobsExplorerBloc(repo, searchDebounce: const Duration(milliseconds: 10));
      addTearDown(bloc.close);
      final overview = JobsOverviewCubit(repo);
      addTearDown(overview.close);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: MultiRepositoryProvider(
          providers: [RepositoryProvider<JobsRepository>.value(value: repo)],
          child: MultiBlocProvider(
            providers: [BlocProvider.value(value: bloc), BlocProvider.value(value: overview)],
            child: JobsNavigation(goTo: (_) {}, explore: (_) {}, child: const Scaffold(body: JobsExplorerTab())),
          ),
        ),
      ));
      bloc.add(const JobsExplorerStarted());
      await tester.pumpAndSettle();
      return (repo, bloc);
    }

    testWidgets('lists the first page with a count, from the server', (tester) async {
      final (repo, _) = await pumpExplorer(tester);
      expect(find.text('Flutter Developer 1'), findsOneWidget);
      expect(find.text('Flutter Developer 3'), findsOneWidget);
      expect(find.text('3 jobs'), findsOneWidget);
      expect(repo.jobQueries.single.filters.view, JobView.active);
      for (final v in ['Active', 'New', 'Saved', 'Applied', 'Rejected', 'Expired', 'All']) {
        expect(find.widgetWithText(JobChoicePill, v), findsOneWidget, reason: v);
      }
    });

    testWidgets('a quick view re-queries the server; an empty view says so', (tester) async {
      final (repo, _) = await pumpExplorer(tester);
      await tester.tap(find.widgetWithText(JobChoicePill, 'Saved'));
      await tester.pumpAndSettle();
      expect(repo.jobQueries.last.filters.view, JobView.saved);
      expect(find.textContaining('Nothing in "Saved"'), findsOneWidget);
      await tester.tap(find.widgetWithText(JobChoicePill, 'Active'));
      await tester.pumpAndSettle();
      expect(find.text('Flutter Developer 1'), findsOneWidget);
    });

    testWidgets('searching is debounced and sent to the server', (tester) async {
      final (repo, _) = await pumpExplorer(tester);
      await tester.enterText(find.byType(TextField).first, 'Developer 2');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(repo.jobQueries.last.filters.query, 'Developer 2');
      expect(find.text('Flutter Developer 2'), findsOneWidget);
      expect(find.text('Flutter Developer 1'), findsNothing);
    });

    testWidgets('saving a job from its card reaches the server and the card shows it', (tester) async {
      final (repo, _) = await pumpExplorer(tester);
      await tester.tap(find.text('Save').first);
      await tester.pumpAndSettle();
      expect(repo.actions, ['app:1:saved']);
      expect(find.text('Saved'), findsWidgets);
    });

    testWidgets('ticking jobs shows the selection bar with export', (tester) async {
      await pumpExplorer(tester);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Export selected'), findsOneWidget);
      await tester.tap(find.text('Select all loaded'));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.text('Clear').last);
      await tester.pump();
      expect(find.text('Export selected'), findsNothing);
    });

    testWidgets('no jobs yet leads to setting up a search', (tester) async {
      await pumpExplorer(tester, jobs: const []);
      expect(find.text('No jobs found yet'), findsOneWidget);
      expect(find.text('Set up a search'), findsOneWidget);
    });

    testWidgets('a server error shows a retry banner, not a blank page', (tester) async {
      _size(tester, 1000);
      final repo = FakeJobsRepository()..failJobs = true;
      final bloc = JobsExplorerBloc(repo);
      addTearDown(bloc.close);
      final overview = JobsOverviewCubit(repo);
      addTearDown(overview.close);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: MultiRepositoryProvider(
          providers: [RepositoryProvider<JobsRepository>.value(value: repo)],
          child: MultiBlocProvider(providers: [BlocProvider.value(value: bloc), BlocProvider.value(value: overview)], child: JobsNavigation(goTo: (_) {}, explore: (_) {}, child: const Scaffold(body: JobsExplorerTab()))),
        ),
      ));
      bloc.add(const JobsExplorerStarted());
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the server.'), findsOneWidget);
      repo.failJobs = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Flutter Developer 1'), findsNothing, reason: 'the fake has no jobs, but the error is gone');
      expect(find.text('Could not reach the server.'), findsNothing);
    });
  });

  testWidgets('Jobs is in the sidebar and opens the Jobs Finder hub with its six tabs', (tester) async {
    _size(tester, 1300, 1000);
    final repo = FakeJobsRepository(jobs: [fakeJob('1')]);
    appRouter.go('/jobs');
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<LeadRepository>.value(value: _NoLeads()),
        RepositoryProvider<JobsRepository>.value(value: repo),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: appRouter),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Jobs Finder'), findsWidgets, reason: 'the sidebar item and the hub title');
    for (final tab in ['Overview', 'Search', 'Scans', 'Tracker', 'Sources']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(find.text('Jobs'), findsWidgets, reason: 'the explorer tab');
    // The Overview opens first and loads its numbers.
    expect(find.text('Jobs discovered'), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);

    // Opening the Jobs tab loads the explorer, once.
    await tester.tap(find.widgetWithText(InkWell, 'Jobs').last);
    await tester.pumpAndSettle();
    expect(find.text('Flutter Developer 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
