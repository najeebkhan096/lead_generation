import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/data/datasources/jobs_remote_datasource.dart';
import 'package:lead_generation_app/domain/entities/job_application.dart';
import 'package:lead_generation_app/domain/entities/job_filters.dart';
import 'package:lead_generation_app/domain/entities/job_scan.dart';
import 'package:lead_generation_app/domain/entities/job_search.dart';
import 'package:lead_generation_app/domain/entities/paged.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/explorer/jobs_explorer_bloc.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/explorer/jobs_explorer_event.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/explorer/jobs_explorer_state.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/job_details_cubit.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/job_tracker_cubit.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/jobs_search_cubit.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/scan/jobs_scan_bloc.dart';
import 'package:lead_generation_app/presentation/bloc/jobs/scan/jobs_scan_event.dart';

import 'support/fake_jobs_repository.dart';

Future<S> until<S>(Stream<S> stream, bool Function(S) test) => stream.firstWhere(test).timeout(const Duration(seconds: 3));

/// Lets queued async work (futures, zero-duration timers) run.
Future<void> settle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

List<String> ids(JobsExplorerState s) => s.jobs.map((j) => j.id).toList();

void main() {
  group('JobsExplorerBloc', () {
    late FakeJobsRepository repo;
    late JobsExplorerBloc bloc;

    setUp(() {
      repo = FakeJobsRepository(jobs: [for (var i = 1; i <= 7; i++) fakeJob('$i')]);
      bloc = JobsExplorerBloc(repo, pageSize: 3, searchDebounce: const Duration(milliseconds: 10));
    });
    tearDown(() => bloc.close());

    test('loads one page, not the collection, and knows the total', () async {
      bloc.add(const JobsExplorerStarted());
      final s = await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      expect(ids(s), ['1', '2', '3']);
      expect(s.total, 7);
      expect(s.hasMore, isTrue);
      expect(repo.jobQueries.single.limit, 3);
    });

    test('scrolling loads the next pages, without duplicates, until the end', () async {
      bloc.add(const JobsExplorerStarted());
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      bloc.add(const JobsExplorerLoadMore());
      bloc.add(const JobsExplorerLoadMore()); // ignored while the first is in flight
      var s = await until(bloc.stream, (s) => s.jobs.length == 6 && !s.loadingMore);
      expect(ids(s), ['1', '2', '3', '4', '5', '6']);
      bloc.add(const JobsExplorerLoadMore());
      s = await until(bloc.stream, (s) => s.jobs.length == 7 && !s.loadingMore);
      expect(s.hasMore, isFalse);
      bloc.add(const JobsExplorerLoadMore());
      await settle();
      expect(repo.jobQueries.length, 3, reason: 'no request past the last page');
      expect(repo.jobQueries[1].cursor, '3');
    });

    test('changing a filter reloads from the first page with the new query', () async {
      bloc.add(const JobsExplorerStarted());
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      bloc.add(const JobsExplorerFiltersChanged(JobFilters(view: JobView.all, city: 'Los Angeles')));
      final s = await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success && s.filters.view == JobView.all);
      expect(repo.jobQueries.last.filters.city, 'Los Angeles');
      expect(repo.jobQueries.last.cursor, isNull);
      expect(s.jobs, hasLength(3));
    });

    test('a slow answer to an old filter never overwrites the newer one', () async {
      repo.jobDelay = (f) => f.query == 'slow' ? const Duration(milliseconds: 120) : Duration.zero;
      bloc.add(const JobsExplorerFiltersChanged(JobFilters(query: 'slow')));
      await settle(10);
      bloc.add(const JobsExplorerFiltersChanged(JobFilters(query: 'Flutter Developer 2')));
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success && s.filters.query == 'Flutter Developer 2');
      await settle(200);
      expect(ids(bloc.state), ['2']);
      expect(bloc.state.filters.query, 'Flutter Developer 2');
    });

    test('typing is debounced into a single search', () async {
      bloc.add(const JobsExplorerStarted());
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      final before = repo.jobQueries.length;
      for (final q in ['f', 'fl', 'flutter developer 5']) {
        bloc.add(JobsExplorerQueryChanged(q));
      }
      await until(bloc.stream, (s) => s.filters.query == 'flutter developer 5' && s.status == JobsExplorerStatus.success);
      expect(repo.jobQueries.length, before + 1);
      expect(ids(bloc.state), ['5']);
    });

    test('saving a job in the "New" view moves it out of the view; the server is told', () async {
      bloc.add(const JobsExplorerFiltersChanged(JobFilters(view: JobView.newJobs)));
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success && s.jobs.isNotEmpty);
      bloc.add(const JobsExplorerTriaged('2', JobTriage.save));
      final s = await until(bloc.stream, (s) => !s.jobs.any((j) => j.id == '2') && s.busy.isEmpty);
      expect(repo.actions, ['app:2:saved']);
      expect(ids(s), ['1', '3']);
      expect(s.total, 6);
      expect(s.message, 'Saved');
    });

    test('in the "All" view a triaged job stays and shows its new state', () async {
      bloc.add(const JobsExplorerFiltersChanged(JobFilters(view: JobView.all)));
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success && s.jobs.isNotEmpty);
      bloc.add(const JobsExplorerTriaged('1', JobTriage.applied));
      var s = await until(bloc.stream, (s) => s.jobs.first.userState == 'applied');
      expect(s.jobs.first.applicationStage, 'applied');
      bloc.add(const JobsExplorerTriaged('1', JobTriage.expired));
      s = await until(bloc.stream, (s) => s.jobs.first.status == 'expired');
      expect(repo.actions, ['app:1:applied', 'status:1:expired']);
      expect(s.jobs.first.isExpired, isTrue);
    });

    test('delete removes the job; a failed action keeps it and reports why', () async {
      bloc.add(const JobsExplorerStarted());
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      bloc.add(const JobsExplorerTriaged('1', JobTriage.delete));
      var s = await until(bloc.stream, (s) => !s.jobs.any((j) => j.id == '1') && s.busy.isEmpty);
      expect(s.total, 6);

      repo.actionError = const JobsApiException('Job not found', status: 404);
      bloc.add(const JobsExplorerTriaged('2', JobTriage.save));
      s = await until(bloc.stream, (s) => s.messageIsError && s.busy.isEmpty);
      expect(s.message, 'Job not found');
      expect(ids(s), contains('2'));
    });

    test('selection: toggle, select the loaded, clear; reloading drops selections that left the list', () async {
      bloc.add(const JobsExplorerStarted());
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      bloc.add(const JobsExplorerToggled('2'));
      var s = await until(bloc.stream, (s) => s.selected.contains('2'));
      bloc.add(const JobsExplorerToggled('2'));
      s = await until(bloc.stream, (s) => s.selected.isEmpty);
      bloc.add(const JobsExplorerSelectLoaded());
      s = await until(bloc.stream, (s) => s.allLoadedSelected);
      expect(s.selected, {'1', '2', '3'});
      bloc.add(const JobsExplorerFiltersChanged(JobFilters(query: 'Flutter Developer 6')));
      s = await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success && s.filters.query != null);
      expect(s.selected, isEmpty, reason: 'a new filter starts a new selection');
    });

    test('a failed load shows the error and can be retried', () async {
      repo.failJobs = true;
      bloc.add(const JobsExplorerStarted());
      var s = await until(bloc.stream, (s) => s.status == JobsExplorerStatus.failure);
      expect(s.error, 'Could not reach the server.');
      repo.failJobs = false;
      bloc.add(const JobsExplorerRefreshed());
      s = await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      expect(s.jobs, isNotEmpty);
      expect(s.error, isNull);
    });

    test('a refresh keeps the list on screen while it reloads', () async {
      bloc.add(const JobsExplorerStarted());
      await until(bloc.stream, (s) => s.status == JobsExplorerStatus.success);
      repo.jobDelay = (_) => const Duration(milliseconds: 50);
      bloc.add(const JobsExplorerRefreshed());
      final loading = await until(bloc.stream, (s) => s.loading);
      expect(loading.jobs, isNotEmpty);
      expect(loading.hasMore, isTrue);
    });
  });

  group('JobsScanBloc', () {
    late FakeJobsRepository repo;
    late JobsScanBloc bloc;

    setUp(() {
      repo = FakeJobsRepository();
      bloc = JobsScanBloc(repo, fastPoll: const Duration(milliseconds: 20), slowPoll: const Duration(milliseconds: 60));
    });
    tearDown(() => bloc.close());

    test('starting a scan adds it to the running list and selects it', () async {
      bloc.add(const JobsScanStarted());
      await until(bloc.stream, (s) => !s.loading);
      bloc.add(const JobsScanBegin('s1'));
      final s = await until(bloc.stream, (s) => s.active.isNotEmpty && !s.starting);
      expect(repo.actions, ['start:s1']);
      expect(s.selectedId, 'run-1');
      expect(s.message, contains('10 searches'));
      expect(s.messageIsError, isFalse);
    });

    test('a refused start (already running) explains why and starts nothing', () async {
      repo.startError = const JobsApiException('This search already has an active scan (r_1)', status: 409);
      bloc.add(const JobsScanBegin('s1'));
      final s = await until(bloc.stream, (s) => s.message != null);
      expect(s.message, contains('already has an active scan'));
      expect(s.messageIsError, isTrue);
      expect(s.active, isEmpty);
    });

    test('it follows a running scan and notices when it finishes', () async {
      repo.activeData = [JobScan.fromJson(scanJson('run-1'))];
      repo.historyData = const Paged<JobScan>(items: []);
      bloc.add(const JobsScanStarted());
      await until(bloc.stream, (s) => s.active.length == 1);
      final polls = repo.activeCalls;
      await settle(100);
      expect(repo.activeCalls, greaterThan(polls), reason: 'polls while a scan runs');

      repo.activeData = [];
      repo.historyData = Paged<JobScan>(items: [JobScan.fromJson(scanJson('run-1', status: 'completed', done: 10))]);
      final s = await until(bloc.stream, (s) => s.active.isEmpty && s.finishedTick == 1);
      expect(s.history.items.single.status, 'completed');
    });

    test('pause, resume and stop go to the server and update the scan', () async {
      repo.activeData = [JobScan.fromJson(scanJson('run-1'))];
      bloc.add(const JobsScanStarted());
      await until(bloc.stream, (s) => s.active.length == 1);
      bloc.add(const JobsScanPause('run-1'));
      var s = await until(bloc.stream, (s) => s.active.first.status == 'paused');
      expect(s.active.first.canResume, isTrue);
      bloc.add(const JobsScanResume('run-1'));
      s = await until(bloc.stream, (s) => s.active.first.status == 'running');
      bloc.add(const JobsScanStop('run-1'));
      s = await until(bloc.stream, (s) => s.active.first.status == 'stopping');
      expect(repo.actions, ['pause:run-1', 'resume:run-1', 'stop:run-1']);
    });
  });

  group('JobsSearchCubit', () {
    late FakeJobsRepository repo;
    late JobsSearchCubit cubit;

    setUp(() {
      repo = FakeJobsRepository();
      cubit = JobsSearchCubit(repo, estimateDelay: const Duration(milliseconds: 10));
    });
    tearDown(() => cubit.close());

    JobCountrySelection us() => cubit.state.draft.countries.firstWhere((c) => c.code == 'US');

    test('loads the countries, saved searches and sources', () async {
      repo.savedSearches = [const JobSearch(id: 's1', name: 'Saved one')];
      await cubit.load();
      expect(cubit.state.countries.map((c) => c.code), ['US', 'QA', 'WW']);
      expect(cubit.state.saved.single.name, 'Saved one');
      expect(cubit.state.sources.map((s) => s.id), ['greenhouse', 'adzuna']);
    });

    test('adding a country loads its states; worldwide is remote-only', () async {
      await cubit.load();
      await cubit.addCountry(repo.countriesData[0]);
      expect(us().level, JobSearchLevel.state);
      expect(us().allRegions, isTrue);
      expect(cubit.state.regions['US']!.map((r) => r.name), ['California', 'Texas', 'New York']);
      await cubit.addCountry(repo.countriesData[2]);
      expect(cubit.state.draft.countries.last.isWorldwide, isTrue);
      expect(cubit.state.draft.countries.last.includeRemote, isTrue);
      await cubit.addCountry(repo.countriesData[0]);
      expect(cubit.state.draft.countries, hasLength(2), reason: 'a country is added once');
      cubit.removeCountry('WW');
      expect(cubit.state.draft.countries.single.code, 'US');
    });

    test('states: all → choose → toggle → select all → deselect all', () async {
      await cubit.load();
      await cubit.addCountry(repo.countriesData[0]);
      cubit.pickRegions('US');
      expect(us().allRegions, isFalse);
      expect(us().regions, isEmpty);
      cubit.toggleRegion('US', 'Texas');
      cubit.toggleRegion('US', 'California');
      expect(us().regions, ['Texas', 'California']);
      cubit.toggleRegion('US', 'Texas');
      expect(us().regions, ['California']);
      cubit.selectAllListedRegions('US');
      expect(us().regions, hasLength(3));
      cubit.clearRegions('US');
      expect(us().regions, isEmpty);
      cubit.setAllRegions('US');
      expect(us().allRegions, isTrue);
    });

    test('cities: pick across states, select a whole state, and removing a state drops its cities', () async {
      await cubit.load();
      await cubit.addCountry(repo.countriesData[0]);
      cubit.setLevel('US', JobSearchLevel.city);
      cubit.pickRegions('US');
      cubit.toggleRegion('US', 'California');
      cubit.toggleRegion('US', 'Texas');
      await cubit.loadCities('US', 'California');
      await cubit.loadCities('US', 'Texas');
      expect(cubit.state.cities['US|California']!.cities, hasLength(3));

      cubit.pickCities('US');
      cubit.toggleCity('US', 'Texas', 'Austin');
      expect(us().allCities, isFalse);
      expect(us().cities, [const JobCityPick('Texas', 'Austin')]);
      cubit.selectRegionCities('US', 'California', selected: true);
      expect(us().cities, hasLength(4));
      cubit.toggleCity('US', 'California', 'San Diego');
      expect(us().cities.where((c) => c.state == 'California'), hasLength(2));
      cubit.selectRegionCities('US', 'California', selected: false);
      expect(us().cities.map((c) => c.city), ['Austin']);
      cubit.selectRegionCities('US', 'California', selected: true);
      cubit.toggleRegion('US', 'California'); // take California out of the search
      expect(us().cities.map((c) => c.state).toSet(), {'Texas'});
      cubit.setAllCities('US');
      expect(us().allCities, isTrue);
      expect(us().cities, isEmpty);
    });

    test('titles and keywords: trimmed, de-duplicated ignoring case', () async {
      cubit.addTitle('  Flutter Developer ');
      cubit.addTitle('flutter developer');
      cubit.addTitle('');
      cubit.addTitle('Senior Flutter Developer');
      expect(cubit.state.draft.titles, ['Flutter Developer', 'Senior Flutter Developer']);
      cubit.removeTitle('Flutter Developer');
      expect(cubit.state.draft.titles, ['Senior Flutter Developer']);
      cubit.addKeyword('Dart');
      cubit.addKeyword('dart');
      expect(cubit.state.draft.keywords, ['Dart']);
    });

    test('the number of searches is asked for after edits (debounced), and only when it can be computed', () async {
      await cubit.load();
      cubit.addTitle('Flutter Developer');
      await settle();
      expect(repo.estimates, isEmpty, reason: 'no country yet');
      await cubit.addCountry(repo.countriesData[0]);
      cubit.addTitle('Senior Flutter Developer');
      cubit.setName('x');
      await until(cubit.stream, (s) => s.estimate != null && !s.estimating);
      expect(repo.estimates, hasLength(1), reason: 'rapid edits collapse into one request');
      expect(repo.estimates.single.titles, hasLength(2));
      expect(cubit.state.estimate!.combinations, 3);
      cubit.removeCountry('US');
      expect(cubit.state.estimate, isNull);
    });

    test('saving needs a name, a country and a title; success stores it with an id', () async {
      await cubit.load();
      expect(await cubit.save(), isNull);
      expect(cubit.state.message, contains('name'));
      expect(cubit.state.messageIsError, isTrue);

      cubit.setName('Flutter in California');
      await cubit.addCountry(repo.countriesData[0]);
      cubit.addTitle('Flutter Developer');
      final stored = await cubit.save();
      expect(stored?.id, 's-new');
      expect(cubit.state.saved.single.name, 'Flutter in California');
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.draft.id, 's-new');
    });

    test('a rejected save reports each problem and keeps the draft', () async {
      await cubit.load();
      cubit.setName('Flutter');
      await cubit.addCountry(repo.countriesData[0]);
      cubit.addTitle('Dev');
      repo.saveError = const JobsApiException('Validation failed', status: 422, details: [
        {'field': 'limits.concurrency', 'message': 'must be at most 8'},
      ]);
      expect(await cubit.save(), isNull);
      expect(cubit.state.message, 'limits.concurrency: must be at most 8');
      expect(cubit.state.draft.name, 'Flutter');
      expect(cubit.state.saving, isFalse);
    });

    test('deleting the open search resets the form', () async {
      repo.savedSearches = [const JobSearch(id: 's1', name: 'One', titles: ['A'], countries: [JobCountrySelection(code: 'US', name: 'United States')])];
      await cubit.load();
      await cubit.edit(cubit.state.saved.first);
      expect(cubit.state.draft.id, 's1');
      await cubit.delete('s1');
      expect(cubit.state.saved, isEmpty);
      expect(cubit.state.draft.id, isNull);
      expect(repo.actions, contains('deleteSearch:s1'));
    });
  });

  group('JobTrackerCubit', () {
    test('moving an application updates the board at once and tells the server; a failure rolls back', () async {
      final repo = FakeJobsRepository();
      final app = JobApplication.fromJson({'jobId': 'j1', 'stage': 'saved', 'job': {'title': 'Dev', 'companyName': 'Co'}});
      repo.applicationsData = {ApplicationStage.saved: [app]};
      final cubit = JobTrackerCubit(repo);
      await cubit.load();
      expect(cubit.state.counts[ApplicationStage.saved], 1);

      await cubit.move(app, ApplicationStage.interview);
      expect(cubit.state.columns[ApplicationStage.saved]!.items, isEmpty);
      expect(cubit.state.columns[ApplicationStage.interview]!.items.single.jobId, 'j1');
      expect(cubit.state.counts[ApplicationStage.interview], 1);
      expect(cubit.state.counts[ApplicationStage.saved], 0);
      expect(repo.actions, ['app:j1:interview']);

      repo.actionError = const JobsApiException('nope');
      final moved = cubit.state.columns[ApplicationStage.interview]!.items.single;
      await cubit.move(moved, ApplicationStage.offered);
      expect(cubit.state.columns[ApplicationStage.interview]!.items, hasLength(1), reason: 'rolled back');
      expect(cubit.state.messageIsError, isTrue);
      await cubit.close();
    });
  });

  group('JobDetailsCubit', () {
    test('loads one job and acts on it; the page learns it changed', () async {
      final repo = FakeJobsRepository(jobs: [fakeJob('9')]);
      final cubit = JobDetailsCubit(repo, '9');
      await cubit.load();
      expect(cubit.state.job!.id, '9');
      expect(cubit.state.changed, isFalse);
      await cubit.markExpired();
      expect(cubit.state.job!.status, 'expired');
      expect(cubit.state.changed, isTrue);
      expect(repo.actions, ['status:9:expired']);
      await cubit.close();
    });

    test('an unreachable server leaves an error, not a crash', () async {
      final repo = FakeJobsRepository();
      final cubit = JobDetailsCubit(repo, 'missing');
      await cubit.load();
      expect(cubit.state.job, isNull);
      expect(cubit.state.error, isNotNull);
      await cubit.close();
    });
  });
}
