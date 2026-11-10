import 'package:equatable/equatable.dart';

import 'job_json.dart';

class JobSourceLimits extends Equatable {
  const JobSourceLimits({this.perMinute = 30, this.perDay = 1000, this.maxConcurrent = 2});

  factory JobSourceLimits.fromJson(Map<String, dynamic> j) => JobSourceLimits(
        perMinute: jobInt(j['perMinute']) ?? 30,
        perDay: jobInt(j['perDay']) ?? 1000,
        maxConcurrent: jobInt(j['maxConcurrent']) ?? 2,
      );

  final int perMinute;
  final int perDay;
  final int maxConcurrent;

  @override
  List<Object?> get props => [perMinute, perDay, maxConcurrent];
}

class JobCareerPage extends Equatable {
  const JobCareerPage({required this.url, this.company, this.website, this.linkPattern, this.render = 'auto'});

  factory JobCareerPage.fromJson(Map<String, dynamic> j) => JobCareerPage(
        url: jobString(j['url']) ?? '',
        company: jobString(j['company']),
        website: jobString(j['website']),
        linkPattern: jobString(j['linkPattern']),
        render: jobString(j['render']) ?? 'auto',
      );

  final String url;
  final String? company;
  final String? website;
  final String? linkPattern;
  final String render;

  Map<String, dynamic> toJson() => {'url': url, 'company': company, 'website': website, 'linkPattern': linkPattern, 'render': render};

  @override
  List<Object?> get props => [url, company, website, linkPattern, render];
}

/// A job source and its integration status. Never carries a key — only
/// whether one is set.
class JobSourceInfo extends Equatable {
  const JobSourceInfo({
    required this.id,
    required this.name,
    this.type = 'api',
    this.description = '',
    this.homepage,
    this.requiresKey = false,
    this.configured = true,
    this.configurationHint,
    this.enabled = true,
    this.limits = const JobSourceLimits(),
    this.boards = const [],
    this.careerPages = const [],
    this.requestsToday = 0,
    this.dailyLimit,
    this.lastRunAt,
    this.lastSuccessAt,
    this.lastError,
    this.consecutiveFailures = 0,
  });

  factory JobSourceInfo.fromJson(Map<String, dynamic> j) {
    final settings = jobMap(j['settings']);
    final usage = jobMap(j['usageToday']);
    final status = jobMap(j['status']);
    final lastError = status['lastError'];
    return JobSourceInfo(
      id: jobString(j['id']) ?? '',
      name: jobString(j['name']) ?? jobString(j['id']) ?? '',
      type: jobString(j['type']) ?? 'api',
      description: jobString(j['description']) ?? '',
      homepage: jobString(j['homepage']),
      requiresKey: j['requiresKey'] == true,
      configured: j['configured'] != false,
      configurationHint: jobString(j['configurationHint']),
      enabled: j['enabled'] != false,
      limits: JobSourceLimits.fromJson(jobMap(j['limits'])),
      boards: [
        for (final b in (settings['boards'] is List ? settings['boards'] as List : const []))
          if (b is Map) jobString(b['id']) ?? '' else if (b is String) b,
      ].where((b) => b.isNotEmpty).toList(),
      careerPages: [for (final c in jobMaps(settings['careerPages'])) JobCareerPage.fromJson(c)],
      requestsToday: jobInt(usage['requests']) ?? 0,
      dailyLimit: jobInt(usage['limit']),
      lastRunAt: jobDate(status['lastRunAt']),
      lastSuccessAt: jobDate(status['lastSuccessAt']),
      lastError: lastError is Map ? jobString(jobMap(lastError)['message']) : jobString(lastError),
      consecutiveFailures: jobInt(status['consecutiveFailures']) ?? 0,
    );
  }

  final String id;
  final String name;

  /// api | ats | feed | career
  final String type;
  final String description;
  final String? homepage;
  final bool requiresKey;

  /// Has what it needs (API key set, boards listed).
  final bool configured;
  final String? configurationHint;
  final bool enabled;
  final JobSourceLimits limits;
  final List<String> boards;
  final List<JobCareerPage> careerPages;
  final int requestsToday;
  final int? dailyLimit;
  final DateTime? lastRunAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final int consecutiveFailures;

  bool get usesBoards => type == 'ats';
  bool get usesCareerPages => type == 'career';

  @override
  List<Object?> get props => [id, enabled, configured, limits, boards, careerPages, requestsToday, lastRunAt, lastError, consecutiveFailures];
}

class JobCompany extends Equatable {
  const JobCompany({required this.id, required this.name, this.website, this.countries = const [], this.sources = const [], this.jobCount, this.activeJobCount, this.lastSeenAt, this.key});

  factory JobCompany.fromJson(Map<String, dynamic> j) => JobCompany(
        id: jobString(j['id']) ?? '',
        key: jobString(j['key']),
        name: jobString(j['name']) ?? 'Unknown company',
        website: jobString(j['website']),
        countries: jobStrings(j['countries']),
        sources: jobStrings(j['sources']),
        jobCount: jobInt(j['jobCount']),
        activeJobCount: jobInt(j['activeJobCount']),
        lastSeenAt: jobDate(j['lastSeenAt']),
      );

  final String id;
  final String? key;
  final String name;
  final String? website;
  final List<String> countries;
  final List<String> sources;
  final int? jobCount;
  final int? activeJobCount;
  final DateTime? lastSeenAt;

  @override
  List<Object?> get props => [id, name, website, jobCount, activeJobCount, lastSeenAt];
}

/// A saved alert: a filter that is checked against each scan's new jobs.
class JobAlert extends Equatable {
  const JobAlert({required this.id, required this.name, this.enabled = true, this.filters = const {}, this.lastMatchAt, this.lastMatchCount = 0, this.totalMatches = 0});

  factory JobAlert.fromJson(Map<String, dynamic> j) => JobAlert(
        id: jobString(j['id']) ?? '',
        name: jobString(j['name']) ?? 'Alert',
        enabled: j['enabled'] != false,
        filters: jobMap(j['filters']),
        lastMatchAt: jobDate(j['lastMatchAt']),
        lastMatchCount: jobInt(j['lastMatchCount']) ?? 0,
        totalMatches: jobInt(j['totalMatches']) ?? 0,
      );

  final String id;
  final String name;
  final bool enabled;
  final Map<String, dynamic> filters;
  final DateTime? lastMatchAt;
  final int lastMatchCount;
  final int totalMatches;

  /// "flutter · remote · Qatar" from the filters that are set.
  String get summary {
    final f = filters;
    final parts = <String>[
      if (jobString(f['q']) != null) jobString(f['q'])!,
      if (jobString(f['workArrangement']) != null) humanize(jobString(f['workArrangement'])),
      if (jobString(f['city']) != null) jobString(f['city'])!,
      if (jobString(f['state']) != null) jobString(f['state'])!,
      if (jobString(f['countryCode']) != null) jobString(f['countryCode'])!,
    ];
    return parts.isEmpty ? 'Every new job' : parts.join(' · ');
  }

  @override
  List<Object?> get props => [id, name, enabled, filters, lastMatchAt, lastMatchCount, totalMatches];
}

/// The result of comparing a CV with a job (on demand; never during a scan).
class JobMatch extends Equatable {
  const JobMatch({required this.score, this.matchingSkills = const [], this.missingSkills = const [], this.requiredYears, this.candidateYears, this.experienceCompatible, this.relevantRequirements = const [], this.suggestions = const [], this.provider = 'keyword'});

  factory JobMatch.fromJson(Map<String, dynamic> j) {
    final exp = jobMap(j['experience']);
    return JobMatch(
      score: jobInt(j['score']) ?? 0,
      matchingSkills: jobStrings(j['matchingSkills']),
      missingSkills: jobStrings(j['missingSkills']),
      requiredYears: jobInt(exp['requiredYears']),
      candidateYears: jobInt(exp['candidateYears']),
      experienceCompatible: exp['compatible'] is bool ? exp['compatible'] as bool : null,
      relevantRequirements: jobStrings(j['relevantRequirements']),
      suggestions: jobStrings(j['suggestions']),
      provider: jobString(j['provider']) ?? 'keyword',
    );
  }

  final int score;
  final List<String> matchingSkills;
  final List<String> missingSkills;
  final int? requiredYears;
  final int? candidateYears;
  final bool? experienceCompatible;
  final List<String> relevantRequirements;
  final List<String> suggestions;
  final String provider;

  @override
  List<Object?> get props => [score, matchingSkills, missingSkills, requiredYears, candidateYears, experienceCompatible, relevantRequirements, suggestions, provider];
}
