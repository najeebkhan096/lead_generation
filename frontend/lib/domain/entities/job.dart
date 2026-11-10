import 'package:equatable/equatable.dart';

import 'job_json.dart';

/// Where a job was found. A job found on several sites has one per site.
class JobSourceRef extends Equatable {
  const JobSourceRef({
    required this.source,
    required this.sourceJobId,
    this.sourceUrl,
    this.applyUrl,
    this.firstSeenAt,
    this.lastSeenAt,
    this.missedChecks = 0,
  });

  factory JobSourceRef.fromJson(Map<String, dynamic> j) => JobSourceRef(
        source: jobString(j['source']) ?? '',
        sourceJobId: jobString(j['sourceJobId']) ?? '',
        sourceUrl: jobString(j['sourceUrl']),
        applyUrl: jobString(j['applyUrl']),
        firstSeenAt: jobDate(j['firstSeenAt']),
        lastSeenAt: jobDate(j['lastSeenAt']),
        missedChecks: jobInt(j['missedChecks']) ?? 0,
      );

  final String source;
  final String sourceJobId;
  final String? sourceUrl;
  final String? applyUrl;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final int missedChecks;

  @override
  List<Object?> get props => [source, sourceJobId, sourceUrl, applyUrl, firstSeenAt, lastSeenAt, missedChecks];
}

/// A normalized job posting. Anything the source did not state is `null`.
class Job extends Equatable {
  const Job({
    required this.id,
    required this.title,
    required this.companyName,
    this.companyKey,
    this.companyWebsite,
    this.locationText,
    this.country,
    this.countryCode,
    this.state,
    this.city,
    this.salaryMin,
    this.salaryMax,
    this.salaryCurrency,
    this.salaryPeriod,
    this.employmentType,
    this.experienceLevel,
    this.experienceYearsMin,
    this.experienceText,
    this.educationText,
    this.requiredSkills = const [],
    this.preferredSkills = const [],
    this.descriptionPreview,
    this.description,
    this.responsibilities,
    this.postedAt,
    this.deadlineAt,
    this.workArrangement,
    this.recruiter,
    this.sourceNames = const [],
    this.sourceUrl,
    this.applyUrl,
    this.status = 'active',
    this.userState = 'new',
    this.applicationStage,
    this.notes,
    this.discoveredAt,
    this.lastVerifiedAt,
    this.sources = const [],
    this.sourceCount = 0,
  });

  factory Job.fromJson(Map<String, dynamic> j) {
    final sources = jobMaps(j['sources']).map(JobSourceRef.fromJson).toList();
    final names = jobStrings(j['sourceNames']);
    return Job(
      id: jobString(j['id']) ?? '',
      title: jobString(j['title']) ?? 'Untitled',
      companyName: jobString(j['companyName']) ?? 'Unknown company',
      companyKey: jobString(j['companyKey']),
      companyWebsite: jobString(j['companyWebsite']),
      locationText: jobString(j['locationText']),
      country: jobString(j['country']),
      countryCode: jobString(j['countryCode']),
      state: jobString(j['state']),
      city: jobString(j['city']),
      salaryMin: jobDouble(j['salaryMin']),
      salaryMax: jobDouble(j['salaryMax']),
      salaryCurrency: jobString(j['salaryCurrency']),
      salaryPeriod: jobString(j['salaryPeriod']),
      employmentType: jobString(j['employmentType']),
      experienceLevel: jobString(j['experienceLevel']),
      experienceYearsMin: jobInt(j['experienceYearsMin']),
      experienceText: jobString(j['experienceText']),
      educationText: jobString(j['educationText']),
      requiredSkills: jobStrings(j['requiredSkills']),
      preferredSkills: jobStrings(j['preferredSkills']),
      descriptionPreview: jobString(j['descriptionPreview']),
      description: jobString(j['description']),
      responsibilities: j['responsibilities'] == null ? null : jobStrings(j['responsibilities']),
      postedAt: jobDate(j['postedAt']),
      deadlineAt: jobDate(j['deadlineAt']),
      workArrangement: jobString(j['workArrangement']),
      recruiter: j['recruiter'] is Map ? jobMap(j['recruiter']) : null,
      sourceNames: names.isNotEmpty ? names : [for (final s in sources) s.source],
      sourceUrl: jobString(j['sourceUrl']),
      applyUrl: jobString(j['applyUrl']),
      status: jobString(j['status']) ?? 'active',
      userState: jobString(j['userState']) ?? 'new',
      applicationStage: jobString(j['applicationStage']),
      notes: jobString(j['notes']),
      discoveredAt: jobDate(j['discoveredAt']),
      lastVerifiedAt: jobDate(j['lastVerifiedAt']),
      sources: sources,
      sourceCount: jobInt(j['sourceCount']) ?? sources.length,
    );
  }

  final String id;
  final String title;
  final String companyName;
  final String? companyKey;
  final String? companyWebsite;
  final String? locationText;
  final String? country;
  final String? countryCode;
  final String? state;
  final String? city;
  final double? salaryMin;
  final double? salaryMax;
  final String? salaryCurrency;
  final String? salaryPeriod;
  final String? employmentType;
  final String? experienceLevel;
  final int? experienceYearsMin;
  final String? experienceText;
  final String? educationText;
  final List<String> requiredSkills;
  final List<String> preferredSkills;
  final String? descriptionPreview;

  /// Only present when the job was loaded with its details.
  final String? description;
  final List<String>? responsibilities;
  final DateTime? postedAt;
  final DateTime? deadlineAt;
  final String? workArrangement;
  final Map<String, dynamic>? recruiter;
  final List<String> sourceNames;

  /// The original posting.
  final String? sourceUrl;

  /// A direct application link at the employer / ATS, when the source gave one.
  final String? applyUrl;
  final String status;
  final String userState;
  final String? applicationStage;
  final String? notes;
  final DateTime? discoveredAt;
  final DateTime? lastVerifiedAt;
  final List<JobSourceRef> sources;
  final int sourceCount;

  bool get isExpired => status != 'active';
  bool get hasSalary => salaryMin != null || salaryMax != null;

  /// "San Francisco, California, United States" from whatever is known; falls
  /// back to the posting's own location text.
  String get placeLabel {
    final parts = <String>[?city, if (state != city) ?state, ?country];
    if (parts.isNotEmpty) return parts.join(', ');
    return locationText ?? 'Location not stated';
  }

  /// "USD 120,000 – 150,000 / year", or `null` when no pay was published.
  String? get salaryLabel {
    if (!hasSalary) return null;
    final lo = salaryMin, hi = salaryMax;
    String n(double v) => thousands(v.round());
    final range = (lo != null && hi != null && lo != hi) ? '${n(lo)} – ${n(hi)}' : n((lo ?? hi)!);
    final period = salaryPeriod == null ? '' : ' / $salaryPeriod';
    return '${salaryCurrency == null ? '' : '$salaryCurrency '}$range$period';
  }

  /// "3+ years", "Senior", or both; `null` when unstated.
  String? get experienceLabel {
    final years = experienceYearsMin == null ? null : '${experienceYearsMin!}+ years';
    final level = experienceLevel == null ? null : humanize(experienceLevel);
    if (years != null && level != null) return '$level · $years';
    return years ?? level;
  }

  Job copyWith({String? status, String? userState, String? applicationStage, bool clearStage = false, String? notes}) => Job(
        id: id,
        title: title,
        companyName: companyName,
        companyKey: companyKey,
        companyWebsite: companyWebsite,
        locationText: locationText,
        country: country,
        countryCode: countryCode,
        state: state,
        city: city,
        salaryMin: salaryMin,
        salaryMax: salaryMax,
        salaryCurrency: salaryCurrency,
        salaryPeriod: salaryPeriod,
        employmentType: employmentType,
        experienceLevel: experienceLevel,
        experienceYearsMin: experienceYearsMin,
        experienceText: experienceText,
        educationText: educationText,
        requiredSkills: requiredSkills,
        preferredSkills: preferredSkills,
        descriptionPreview: descriptionPreview,
        description: description,
        responsibilities: responsibilities,
        postedAt: postedAt,
        deadlineAt: deadlineAt,
        workArrangement: workArrangement,
        recruiter: recruiter,
        sourceNames: sourceNames,
        sourceUrl: sourceUrl,
        applyUrl: applyUrl,
        status: status ?? this.status,
        userState: userState ?? this.userState,
        applicationStage: clearStage ? null : (applicationStage ?? this.applicationStage),
        notes: notes ?? this.notes,
        discoveredAt: discoveredAt,
        lastVerifiedAt: lastVerifiedAt,
        sources: sources,
        sourceCount: sourceCount,
      );

  @override
  List<Object?> get props => [id, status, userState, applicationStage, notes, lastVerifiedAt, title, companyName, sourceNames];
}
