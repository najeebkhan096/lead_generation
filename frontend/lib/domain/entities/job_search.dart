import 'package:equatable/equatable.dart';

import 'job_json.dart';

/// How deep a country's search goes.
enum JobSearchLevel {
  country('country', 'Whole country'),
  state('state', 'Each state / province'),
  city('city', 'Each city');

  const JobSearchLevel(this.wire, this.label);
  final String wire;
  final String label;

  static JobSearchLevel parse(Object? v) => values.firstWhere((l) => l.wire == v, orElse: () => JobSearchLevel.city);
}

/// A selected city, which is a (state, city) pair — city names repeat across states.
class JobCityPick extends Equatable {
  const JobCityPick(this.state, this.city);

  final String state;
  final String city;

  Map<String, dynamic> toJson() => {'state': state, 'city': city};

  @override
  List<Object?> get props => [state, city];
}

/// One country in a search: how deep to go and which states / cities.
class JobCountrySelection extends Equatable {
  const JobCountrySelection({
    required this.code,
    required this.name,
    this.level = JobSearchLevel.city,
    this.allRegions = true,
    this.regions = const [],
    this.allCities = true,
    this.cities = const [],
    this.includeRemote = false,
  });

  factory JobCountrySelection.fromJson(Map<String, dynamic> j, {String? name}) {
    final regions = j['regions'];
    final cities = j['cities'];
    return JobCountrySelection(
      code: jobString(j['code']) ?? '',
      name: name ?? jobString(j['name']) ?? jobString(j['code']) ?? '',
      level: JobSearchLevel.parse(j['level']),
      allRegions: regions is! List,
      regions: jobStrings(regions),
      allCities: cities is! List,
      cities: cities is List ? [for (final c in jobMaps(cities)) JobCityPick(jobString(c['state']) ?? '', jobString(c['city']) ?? '')] : const [],
      includeRemote: j['includeRemote'] == true,
    );
  }

  final String code;
  final String name;
  final JobSearchLevel level;
  final bool allRegions;
  final List<String> regions;
  final bool allCities;
  final List<JobCityPick> cities;
  final bool includeRemote;

  bool get isWorldwide => code == 'WW';

  JobCountrySelection copyWith({
    JobSearchLevel? level,
    bool? allRegions,
    List<String>? regions,
    bool? allCities,
    List<JobCityPick>? cities,
    bool? includeRemote,
  }) =>
      JobCountrySelection(
        code: code,
        name: name,
        level: level ?? this.level,
        allRegions: allRegions ?? this.allRegions,
        regions: regions ?? this.regions,
        allCities: allCities ?? this.allCities,
        cities: cities ?? this.cities,
        includeRemote: includeRemote ?? this.includeRemote,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        if (!isWorldwide) 'level': level.wire,
        if (!isWorldwide && level != JobSearchLevel.country) 'regions': allRegions ? 'all' : regions,
        if (!isWorldwide && level == JobSearchLevel.city) 'cities': allCities ? 'all' : [for (final c in cities) c.toJson()],
        if (!isWorldwide) 'includeRemote': includeRemote,
      };

  @override
  List<Object?> get props => [code, level, allRegions, regions, allCities, cities, includeRemote];
}

class JobSearchFilters extends Equatable {
  const JobSearchFilters({this.experienceLevel, this.employmentType, this.workArrangement, this.salaryMin, this.salaryMax, this.salaryCurrency, this.postedWithinDays});

  factory JobSearchFilters.fromJson(Map<String, dynamic> j) => JobSearchFilters(
        experienceLevel: jobString(j['experienceLevel']),
        employmentType: jobString(j['employmentType']),
        workArrangement: jobString(j['workArrangement']),
        salaryMin: jobInt(j['salaryMin']),
        salaryMax: jobInt(j['salaryMax']),
        salaryCurrency: jobString(j['salaryCurrency']),
        postedWithinDays: jobInt(j['postedWithinDays']),
      );

  final String? experienceLevel;
  final String? employmentType;
  final String? workArrangement;
  final int? salaryMin;
  final int? salaryMax;
  final String? salaryCurrency;
  final int? postedWithinDays;

  JobSearchFilters copyWith({
    Object? experienceLevel = _keep,
    Object? employmentType = _keep,
    Object? workArrangement = _keep,
    Object? salaryMin = _keep,
    Object? salaryMax = _keep,
    Object? salaryCurrency = _keep,
    Object? postedWithinDays = _keep,
  }) =>
      JobSearchFilters(
        experienceLevel: identical(experienceLevel, _keep) ? this.experienceLevel : experienceLevel as String?,
        employmentType: identical(employmentType, _keep) ? this.employmentType : employmentType as String?,
        workArrangement: identical(workArrangement, _keep) ? this.workArrangement : workArrangement as String?,
        salaryMin: identical(salaryMin, _keep) ? this.salaryMin : salaryMin as int?,
        salaryMax: identical(salaryMax, _keep) ? this.salaryMax : salaryMax as int?,
        salaryCurrency: identical(salaryCurrency, _keep) ? this.salaryCurrency : salaryCurrency as String?,
        postedWithinDays: identical(postedWithinDays, _keep) ? this.postedWithinDays : postedWithinDays as int?,
      );

  Map<String, dynamic> toJson() => {
        'experienceLevel': experienceLevel,
        'employmentType': employmentType,
        'workArrangement': workArrangement,
        'salaryMin': salaryMin,
        'salaryMax': salaryMax,
        'salaryCurrency': salaryCurrency,
        'postedWithinDays': postedWithinDays,
      };

  @override
  List<Object?> get props => [experienceLevel, employmentType, workArrangement, salaryMin, salaryMax, salaryCurrency, postedWithinDays];
}

const Object _keep = Object();

class JobSearchLimits extends Equatable {
  const JobSearchLimits({this.maxCombinations = 20000, this.maxResultsPerCombination = 100, this.maxPagesPerSource = 3, this.concurrency = 3});

  factory JobSearchLimits.fromJson(Map<String, dynamic> j) => JobSearchLimits(
        maxCombinations: jobInt(j['maxCombinations']) ?? 20000,
        maxResultsPerCombination: jobInt(j['maxResultsPerCombination']) ?? 100,
        maxPagesPerSource: jobInt(j['maxPagesPerSource']) ?? 3,
        concurrency: jobInt(j['concurrency']) ?? 3,
      );

  final int maxCombinations;
  final int maxResultsPerCombination;
  final int maxPagesPerSource;
  final int concurrency;

  JobSearchLimits copyWith({int? maxCombinations, int? maxResultsPerCombination, int? maxPagesPerSource, int? concurrency}) => JobSearchLimits(
        maxCombinations: maxCombinations ?? this.maxCombinations,
        maxResultsPerCombination: maxResultsPerCombination ?? this.maxResultsPerCombination,
        maxPagesPerSource: maxPagesPerSource ?? this.maxPagesPerSource,
        concurrency: concurrency ?? this.concurrency,
      );

  Map<String, dynamic> toJson() => {
        'maxCombinations': maxCombinations,
        'maxResultsPerCombination': maxResultsPerCombination,
        'maxPagesPerSource': maxPagesPerSource,
        'concurrency': concurrency,
      };

  @override
  List<Object?> get props => [maxCombinations, maxResultsPerCombination, maxPagesPerSource, concurrency];
}

class JobSchedule extends Equatable {
  const JobSchedule({this.enabled = false, this.timeOfDay = '03:00', this.timezone = 'UTC', this.lastRunDate});

  factory JobSchedule.fromJson(Map<String, dynamic> j) => JobSchedule(
        enabled: j['enabled'] == true,
        timeOfDay: jobString(j['timeOfDay']) ?? '03:00',
        timezone: jobString(j['timezone']) ?? 'UTC',
        lastRunDate: jobString(j['lastRunDate']),
      );

  final bool enabled;
  final String timeOfDay;
  final String timezone;
  final String? lastRunDate;

  JobSchedule copyWith({bool? enabled, String? timeOfDay, String? timezone}) =>
      JobSchedule(enabled: enabled ?? this.enabled, timeOfDay: timeOfDay ?? this.timeOfDay, timezone: timezone ?? this.timezone, lastRunDate: lastRunDate);

  Map<String, dynamic> toJson() => {'enabled': enabled, 'timeOfDay': timeOfDay, 'timezone': timezone};

  @override
  List<Object?> get props => [enabled, timeOfDay, timezone];
}

/// A saved search configuration (`job_searches`).
class JobSearch extends Equatable {
  const JobSearch({
    this.id,
    this.name = '',
    this.enabled = true,
    this.countries = const [],
    this.titles = const [],
    this.keywords = const [],
    this.filters = const JobSearchFilters(),
    this.sources = const [],
    this.limits = const JobSearchLimits(),
    this.schedule = const JobSchedule(),
    this.lastRunAt,
    this.lastRunId,
    this.lastRunStatus,
  });

  factory JobSearch.fromJson(Map<String, dynamic> j, {Map<String, String> countryNames = const {}}) => JobSearch(
        id: jobString(j['id']),
        name: jobString(j['name']) ?? '',
        enabled: j['enabled'] != false,
        countries: [for (final c in jobMaps(j['countries'])) JobCountrySelection.fromJson(c, name: countryNames[c['code']])],
        titles: jobStrings(j['titles']),
        keywords: jobStrings(j['keywords']),
        filters: JobSearchFilters.fromJson(jobMap(j['filters'])),
        sources: jobStrings(j['sources']),
        limits: JobSearchLimits.fromJson(jobMap(j['limits'])),
        schedule: JobSchedule.fromJson(jobMap(j['schedule'])),
        lastRunAt: jobDate(j['lastRunAt']),
        lastRunId: jobString(j['lastRunId']),
        lastRunStatus: jobString(j['lastRunStatus']),
      );

  final String? id;
  final String name;
  final bool enabled;
  final List<JobCountrySelection> countries;
  final List<String> titles;
  final List<String> keywords;
  final JobSearchFilters filters;

  /// Empty = every enabled source.
  final List<String> sources;
  final JobSearchLimits limits;
  final JobSchedule schedule;
  final DateTime? lastRunAt;
  final String? lastRunId;
  final String? lastRunStatus;

  bool get isValid => name.trim().length >= 2 && countries.isNotEmpty && titles.isNotEmpty;

  JobSearch copyWith({
    String? name,
    bool? enabled,
    List<JobCountrySelection>? countries,
    List<String>? titles,
    List<String>? keywords,
    JobSearchFilters? filters,
    List<String>? sources,
    JobSearchLimits? limits,
    JobSchedule? schedule,
  }) =>
      JobSearch(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        countries: countries ?? this.countries,
        titles: titles ?? this.titles,
        keywords: keywords ?? this.keywords,
        filters: filters ?? this.filters,
        sources: sources ?? this.sources,
        limits: limits ?? this.limits,
        schedule: schedule ?? this.schedule,
        lastRunAt: lastRunAt,
        lastRunId: lastRunId,
        lastRunStatus: lastRunStatus,
      );

  /// The request body for create / update / estimate.
  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'enabled': enabled,
        'countries': [for (final c in countries) c.toJson()],
        'titles': titles,
        'keywords': keywords,
        'filters': filters.toJson(),
        'sources': sources,
        'limits': limits.toJson(),
        'schedule': schedule.toJson(),
      };

  @override
  List<Object?> get props => [id, name, enabled, countries, titles, keywords, filters, sources, limits, schedule, lastRunId, lastRunStatus];
}

/// How many searches a draft expands to — shown before anything runs.
class JobEstimate extends Equatable {
  const JobEstimate({this.locations = 0, this.titles = 0, this.combinations = 0, this.withinLimit = true, this.maxCombinations = 0, this.usableSources = const [], this.selectedSources = const []});

  factory JobEstimate.fromJson(Map<String, dynamic> j) {
    final sources = jobMap(j['sources']);
    return JobEstimate(
      locations: jobInt(j['locations']) ?? 0,
      titles: jobInt(j['titles']) ?? 0,
      combinations: jobInt(j['combinations']) ?? 0,
      withinLimit: j['withinLimit'] != false,
      maxCombinations: jobInt(j['maxCombinations']) ?? 0,
      usableSources: jobStrings(sources['usable']),
      selectedSources: jobStrings(sources['selected']),
    );
  }

  final int locations;
  final int titles;
  final int combinations;
  final bool withinLimit;
  final int maxCombinations;
  final List<String> usableSources;
  final List<String> selectedSources;

  @override
  List<Object?> get props => [locations, titles, combinations, withinLimit, maxCombinations, usableSources, selectedSources];
}
