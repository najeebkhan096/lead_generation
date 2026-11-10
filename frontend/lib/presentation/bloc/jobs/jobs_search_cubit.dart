import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/job_geo.dart';
import '../../../domain/entities/job_search.dart';
import '../../../domain/entities/job_source_info.dart';
import '../../../domain/repositories/jobs_repository.dart';
import 'jobs_errors.dart';

class JobsSearchState extends Equatable {
  const JobsSearchState({
    this.loading = true,
    this.countries = const [],
    this.regions = const {},
    this.cities = const {},
    this.loadingGeo = const {},
    this.draft = const JobSearch(),
    this.saved = const [],
    this.sources = const [],
    this.estimate,
    this.estimating = false,
    this.saving = false,
    this.dirty = false,
    this.message,
    this.messageIsError = true,
  });

  final bool loading;
  final List<JobCountry> countries;

  /// By country code, loaded when a country is added.
  final Map<String, List<JobRegion>> regions;

  /// By `CODE|Region`, loaded when a region is opened.
  final Map<String, JobCityList> cities;
  final Set<String> loadingGeo;
  final JobSearch draft;
  final List<JobSearch> saved;
  final List<JobSourceInfo> sources;
  final JobEstimate? estimate;
  final bool estimating;
  final bool saving;

  /// The draft differs from what is stored.
  final bool dirty;
  final String? message;
  final bool messageIsError;

  JobCountry? country(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  static String cityKey(String code, String region) => '$code|$region';

  JobsSearchState copyWith({
    bool? loading,
    List<JobCountry>? countries,
    Map<String, List<JobRegion>>? regions,
    Map<String, JobCityList>? cities,
    Set<String>? loadingGeo,
    JobSearch? draft,
    List<JobSearch>? saved,
    List<JobSourceInfo>? sources,
    Object? estimate = _keep,
    bool? estimating,
    bool? saving,
    bool? dirty,
    Object? message = _keep,
    bool? messageIsError,
  }) =>
      JobsSearchState(
        loading: loading ?? this.loading,
        countries: countries ?? this.countries,
        regions: regions ?? this.regions,
        cities: cities ?? this.cities,
        loadingGeo: loadingGeo ?? this.loadingGeo,
        draft: draft ?? this.draft,
        saved: saved ?? this.saved,
        sources: sources ?? this.sources,
        estimate: identical(estimate, _keep) ? this.estimate : estimate as JobEstimate?,
        estimating: estimating ?? this.estimating,
        saving: saving ?? this.saving,
        dirty: dirty ?? this.dirty,
        message: identical(message, _keep) ? this.message : message as String?,
        messageIsError: messageIsError ?? this.messageIsError,
      );

  @override
  List<Object?> get props => [loading, countries, regions, cities, loadingGeo, draft, saved, sources, estimate, estimating, saving, dirty, message, messageIsError];
}

const Object _keep = Object();

/// The search-configuration form: what to look for, where, and how.
///
/// Country → State / Province → City selections are edited here and the
/// server is asked how many searches they expand to, so the number is known
/// before anything runs.
class JobsSearchCubit extends Cubit<JobsSearchState> {
  JobsSearchCubit(this._repo, {this.estimateDelay = const Duration(milliseconds: 350)}) : super(const JobsSearchState());

  final JobsRepository _repo;
  final Duration estimateDelay;
  Timer? _estimateTimer;
  int _estimateGeneration = 0;

  @override
  Future<void> close() {
    _estimateTimer?.cancel();
    return super.close();
  }

  // ------------------------------------------------------------------ load
  Future<void> load() async {
    emit(state.copyWith(loading: true, message: null));
    try {
      final countries = await _repo.countries();
      final results = await Future.wait<Object>([_repo.searches().then((p) => p.items), _repo.sources()]);
      emit(state.copyWith(loading: false, countries: countries, saved: results[0] as List<JobSearch>, sources: results[1] as List<JobSourceInfo>));
    } catch (e) {
      emit(state.copyWith(loading: false, message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  Future<void> reloadSaved() async {
    try {
      final page = await _repo.searches();
      emit(state.copyWith(saved: page.items));
    } catch (_) {/* the list keeps what it had */}
  }

  Future<void> reloadSources() async {
    try {
      emit(state.copyWith(sources: await _repo.sources()));
    } catch (_) {}
  }

  // ----------------------------------------------------------------- draft
  void _edit(JobSearch draft) {
    emit(state.copyWith(draft: draft, dirty: true, message: null));
    _scheduleEstimate();
  }

  void newSearch() {
    emit(state.copyWith(draft: const JobSearch(), dirty: false, estimate: null, message: null));
  }

  Future<void> edit(JobSearch search) async {
    emit(state.copyWith(draft: search, dirty: false, message: null));
    for (final c in search.countries) {
      if (!c.isWorldwide) unawaited(_loadRegions(c.code));
    }
    _scheduleEstimate(immediately: true);
  }

  void setName(String name) => _edit(state.draft.copyWith(name: name));
  void setEnabled(bool enabled) => _edit(state.draft.copyWith(enabled: enabled));

  // ------------------------------------------------------------- countries
  Future<void> addCountry(JobCountry country) async {
    if (state.draft.countries.any((c) => c.code == country.code)) return;
    final selection = JobCountrySelection(
      code: country.code,
      name: country.name,
      level: country.remoteOnly ? JobSearchLevel.country : JobSearchLevel.state,
      includeRemote: country.remoteOnly,
    );
    _edit(state.draft.copyWith(countries: [...state.draft.countries, selection]));
    if (!country.remoteOnly) await _loadRegions(country.code);
  }

  void removeCountry(String code) => _edit(state.draft.copyWith(countries: state.draft.countries.where((c) => c.code != code).toList()));

  void _updateCountry(String code, JobCountrySelection Function(JobCountrySelection) change) =>
      _edit(state.draft.copyWith(countries: [for (final c in state.draft.countries) c.code == code ? change(c) : c]));

  void setLevel(String code, JobSearchLevel level) => _updateCountry(code, (c) => c.copyWith(level: level));
  void setIncludeRemote(String code, bool value) => _updateCountry(code, (c) => c.copyWith(includeRemote: value));

  // ---------------------------------------------------------------- regions
  Future<void> _loadRegions(String code) async {
    if (state.regions.containsKey(code)) return;
    final key = 'regions:$code';
    emit(state.copyWith(loadingGeo: {...state.loadingGeo, key}));
    try {
      final regions = await _repo.regions(code);
      emit(state.copyWith(regions: {...state.regions, code: regions}, loadingGeo: {...state.loadingGeo}..remove(key)));
    } catch (e) {
      emit(state.copyWith(loadingGeo: {...state.loadingGeo}..remove(key), message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  void setAllRegions(String code) => _updateCountry(code, (c) => c.copyWith(allRegions: true, regions: const [], allCities: true, cities: const []));

  /// Switches to a hand-picked list of regions, starting from none.
  void pickRegions(String code) => _updateCountry(code, (c) => c.copyWith(allRegions: false, regions: c.allRegions ? const [] : c.regions));

  void toggleRegion(String code, String region) => _updateCountry(code, (c) {
        final list = c.allRegions ? <String>[] : [...c.regions];
        if (!list.remove(region)) list.add(region);
        // A region taken out of the search takes its picked cities with it.
        final cities = c.cities.where((p) => list.contains(p.state)).toList();
        return c.copyWith(allRegions: false, regions: list, cities: cities);
      });

  void selectAllListedRegions(String code) {
    final all = state.regions[code] ?? const [];
    _updateCountry(code, (c) => c.copyWith(allRegions: false, regions: [for (final r in all) r.name]));
  }

  void clearRegions(String code) => _updateCountry(code, (c) => c.copyWith(allRegions: false, regions: const [], cities: const []));

  // ----------------------------------------------------------------- cities
  Future<void> loadCities(String code, String region) async {
    final key = JobsSearchState.cityKey(code, region);
    if (state.cities.containsKey(key) || state.loadingGeo.contains(key)) return;
    emit(state.copyWith(loadingGeo: {...state.loadingGeo, key}));
    try {
      final list = await _repo.cities(code, region);
      emit(state.copyWith(cities: {...state.cities, key: list}, loadingGeo: {...state.loadingGeo}..remove(key)));
    } catch (e) {
      emit(state.copyWith(loadingGeo: {...state.loadingGeo}..remove(key), message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  void setAllCities(String code) => _updateCountry(code, (c) => c.copyWith(allCities: true, cities: const []));
  void pickCities(String code) => _updateCountry(code, (c) => c.copyWith(allCities: false, cities: c.allCities ? const [] : c.cities));

  void toggleCity(String code, String region, String city) => _updateCountry(code, (c) {
        final pick = JobCityPick(region, city);
        final list = c.allCities ? <JobCityPick>[] : [...c.cities];
        if (!list.remove(pick)) list.add(pick);
        return c.copyWith(allCities: false, cities: list);
      });

  void selectRegionCities(String code, String region, {required bool selected}) {
    final loaded = state.cities[JobsSearchState.cityKey(code, region)];
    if (loaded == null) return;
    _updateCountry(code, (c) {
      final others = c.allCities ? <JobCityPick>[] : c.cities.where((p) => p.state != region).toList();
      final mine = selected ? [for (final city in loaded.cities) JobCityPick(region, city.name)] : const <JobCityPick>[];
      return c.copyWith(allCities: false, cities: [...others, ...mine]);
    });
  }

  // ----------------------------------------------------- titles & keywords
  void addTitle(String title) {
    final t = title.trim();
    if (t.isEmpty || state.draft.titles.any((x) => x.toLowerCase() == t.toLowerCase())) return;
    _edit(state.draft.copyWith(titles: [...state.draft.titles, t]));
  }

  void removeTitle(String title) => _edit(state.draft.copyWith(titles: state.draft.titles.where((t) => t != title).toList()));

  void addKeyword(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty || state.draft.keywords.any((x) => x.toLowerCase() == k.toLowerCase())) return;
    _edit(state.draft.copyWith(keywords: [...state.draft.keywords, k]));
  }

  void removeKeyword(String keyword) => _edit(state.draft.copyWith(keywords: state.draft.keywords.where((k) => k != keyword).toList()));

  // ------------------------------------------------------ filters & others
  void setFilters(JobSearchFilters filters) => _edit(state.draft.copyWith(filters: filters));
  void setLimits(JobSearchLimits limits) => _edit(state.draft.copyWith(limits: limits));
  void setSchedule(JobSchedule schedule) => _edit(state.draft.copyWith(schedule: schedule));

  /// An empty list means "every enabled source".
  void toggleSource(String id) {
    final current = state.draft.sources;
    final list = current.contains(id) ? current.where((s) => s != id).toList() : [...current, id];
    _edit(state.draft.copyWith(sources: list));
  }

  void useAllSources() => _edit(state.draft.copyWith(sources: const []));

  // --------------------------------------------------------------- estimate
  void _scheduleEstimate({bool immediately = false}) {
    _estimateTimer?.cancel();
    final draft = state.draft;
    if (draft.countries.isEmpty || draft.titles.isEmpty) {
      _estimateGeneration++;
      emit(state.copyWith(estimate: null, estimating: false));
      return;
    }
    emit(state.copyWith(estimating: true));
    _estimateTimer = Timer(immediately ? Duration.zero : estimateDelay, () async {
      final generation = ++_estimateGeneration;
      try {
        final estimate = await _repo.estimate(state.draft);
        if (generation == _estimateGeneration && !isClosed) emit(state.copyWith(estimate: estimate, estimating: false));
      } catch (e) {
        if (generation == _estimateGeneration && !isClosed) emit(state.copyWith(estimate: null, estimating: false, message: jobsErrorMessage(e), messageIsError: true));
      }
    });
  }

  // ------------------------------------------------------------ save/delete
  /// Creates or updates the draft on the server. Returns the stored search, or
  /// `null` if it could not be saved (the reason is in [JobsSearchState.message]).
  Future<JobSearch?> save() async {
    final draft = state.draft;
    if (!draft.isValid) {
      emit(state.copyWith(message: 'Give the search a name, pick at least one country and add at least one job title.', messageIsError: true));
      return null;
    }
    emit(state.copyWith(saving: true, message: null));
    try {
      final stored = draft.id == null ? await _repo.createSearch(draft) : await _repo.updateSearch(draft);
      final saved = [stored, ...state.saved.where((s) => s.id != stored.id)];
      emit(state.copyWith(saving: false, draft: stored, saved: saved, dirty: false, message: 'Search saved.', messageIsError: false));
      return stored;
    } catch (e) {
      emit(state.copyWith(saving: false, message: jobsErrorMessage(e), messageIsError: true));
      return null;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _repo.deleteSearch(id);
      emit(state.copyWith(
        saved: state.saved.where((s) => s.id != id).toList(),
        draft: state.draft.id == id ? const JobSearch() : state.draft,
        estimate: state.draft.id == id ? null : state.estimate,
        message: 'Search deleted.',
        messageIsError: false,
      ));
    } catch (e) {
      emit(state.copyWith(message: jobsErrorMessage(e), messageIsError: true));
    }
  }

  void clearMessage() => emit(state.copyWith(message: null));
}
