import 'package:equatable/equatable.dart';

/// The explorer's quick views: where a job stands for the person triaging.
enum JobView {
  active('Active', {'status': 'active'}),
  newJobs('New', {'userState': 'new', 'status': 'active'}),
  saved('Saved', {'userState': 'saved'}),
  applied('Applied', {'userState': 'applied'}),
  rejected('Rejected', {'userState': 'rejected'}),
  expired('Expired', {'status': 'expired'}),
  all('All', {});

  const JobView(this.label, this.query);
  final String label;
  final Map<String, String> query;
}

enum JobSort {
  discovered('discovered', 'Newest discovered'),
  posted('posted', 'Newest posted'),
  updated('updated', 'Recently updated');

  const JobSort(this.wire, this.label);
  final String wire;
  final String label;
}

/// Every filter of the Jobs Explorer. The server applies them; the app never
/// holds more than the pages it has loaded.
class JobFilters extends Equatable {
  const JobFilters({
    this.view = JobView.active,
    this.countryCode,
    this.state,
    this.city,
    this.company,
    this.query,
    this.skills = const [],
    this.experienceLevel,
    this.employmentType,
    this.workArrangement,
    this.source,
    this.salaryMin,
    this.salaryCurrency,
    this.postedWithinDays,
    this.sort = JobSort.discovered,
    this.runId,
  });

  final JobView view;
  final String? countryCode;
  final String? state;
  final String? city;
  final String? company;
  final String? query;
  final List<String> skills;
  final String? experienceLevel;
  final String? employmentType;
  final String? workArrangement;
  final String? source;
  final int? salaryMin;
  final String? salaryCurrency;
  final int? postedWithinDays;
  final JobSort sort;
  final String? runId;

  bool get hasExtraFilters =>
      countryCode != null ||
      state != null ||
      city != null ||
      company != null ||
      (query?.isNotEmpty ?? false) ||
      skills.isNotEmpty ||
      experienceLevel != null ||
      employmentType != null ||
      workArrangement != null ||
      source != null ||
      salaryMin != null ||
      postedWithinDays != null ||
      runId != null;

  JobFilters copyWith({
    JobView? view,
    Object? countryCode = _keep,
    Object? state = _keep,
    Object? city = _keep,
    Object? company = _keep,
    Object? query = _keep,
    List<String>? skills,
    Object? experienceLevel = _keep,
    Object? employmentType = _keep,
    Object? workArrangement = _keep,
    Object? source = _keep,
    Object? salaryMin = _keep,
    Object? salaryCurrency = _keep,
    Object? postedWithinDays = _keep,
    JobSort? sort,
    Object? runId = _keep,
  }) =>
      JobFilters(
        view: view ?? this.view,
        countryCode: identical(countryCode, _keep) ? this.countryCode : countryCode as String?,
        state: identical(state, _keep) ? this.state : state as String?,
        city: identical(city, _keep) ? this.city : city as String?,
        company: identical(company, _keep) ? this.company : company as String?,
        query: identical(query, _keep) ? this.query : query as String?,
        skills: skills ?? this.skills,
        experienceLevel: identical(experienceLevel, _keep) ? this.experienceLevel : experienceLevel as String?,
        employmentType: identical(employmentType, _keep) ? this.employmentType : employmentType as String?,
        workArrangement: identical(workArrangement, _keep) ? this.workArrangement : workArrangement as String?,
        source: identical(source, _keep) ? this.source : source as String?,
        salaryMin: identical(salaryMin, _keep) ? this.salaryMin : salaryMin as int?,
        salaryCurrency: identical(salaryCurrency, _keep) ? this.salaryCurrency : salaryCurrency as String?,
        postedWithinDays: identical(postedWithinDays, _keep) ? this.postedWithinDays : postedWithinDays as int?,
        sort: sort ?? this.sort,
        runId: identical(runId, _keep) ? this.runId : runId as String?,
      );

  /// A new filter set keeping only the view and sort.
  JobFilters cleared() => JobFilters(view: view, sort: sort);

  /// The query string for `GET /api/jobs`.
  Map<String, String> toQuery() {
    String? s(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final out = <String, String>{...view.query, 'sort': sort.wire};
    void put(String key, String? value) {
      final v = s(value);
      if (v != null) out[key] = v;
    }

    put('country', countryCode);
    put('state', state);
    put('city', city);
    put('company', company);
    put('q', query);
    if (skills.isNotEmpty) out['skills'] = skills.join(',');
    put('experienceLevel', experienceLevel);
    put('employmentType', employmentType);
    put('workArrangement', workArrangement);
    put('source', source);
    if (salaryMin != null) out['salaryMin'] = '$salaryMin';
    put('salaryCurrency', salaryCurrency);
    if (postedWithinDays != null) out['postedWithinDays'] = '$postedWithinDays';
    put('runId', runId);
    return out;
  }

  @override
  List<Object?> get props => [view, countryCode, state, city, company, query, skills, experienceLevel, employmentType, workArrangement, source, salaryMin, salaryCurrency, postedWithinDays, sort, runId];
}

const Object _keep = Object();
