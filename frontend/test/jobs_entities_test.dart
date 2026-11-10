import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/job.dart';
import 'package:lead_generation_app/domain/entities/job_application.dart';
import 'package:lead_generation_app/domain/entities/job_filters.dart';
import 'package:lead_generation_app/domain/entities/job_json.dart';
import 'package:lead_generation_app/domain/entities/job_scan.dart';
import 'package:lead_generation_app/domain/entities/job_search.dart';
import 'package:lead_generation_app/domain/entities/job_source_info.dart';
import 'package:lead_generation_app/domain/entities/job_stats.dart';

import 'support/fake_jobs_repository.dart';

void main() {
  group('Job', () {
    test('unknown facts stay null — nothing is made up', () {
      final j = Job.fromJson({'id': 'a', 'title': 'Barista', 'companyName': 'Cafe'});
      expect(j.salaryMin, isNull);
      expect(j.salaryLabel, isNull);
      expect(j.employmentType, isNull);
      expect(j.workArrangement, isNull);
      expect(j.postedAt, isNull);
      expect(j.applyUrl, isNull);
      expect(j.experienceLabel, isNull);
      expect(j.requiredSkills, isEmpty);
      expect(j.placeLabel, 'Location not stated');
      expect(j.status, 'active');
      expect(j.userState, 'new');
    });

    test('salary, place and experience read naturally', () {
      final j = fakeJob('1', extra: {
        'salaryMin': 120000, 'salaryMax': 150000.0, 'salaryCurrency': 'USD', 'salaryPeriod': 'year',
        'experienceLevel': 'senior', 'experienceYearsMin': 5,
      });
      expect(j.salaryLabel, 'USD 120,000 – 150,000 / year');
      expect(j.placeLabel, 'Los Angeles, California, United States');
      expect(j.experienceLabel, 'Senior · 5+ years');
      expect(fakeJob('2', extra: {'salaryMin': 30, 'salaryMax': 30, 'salaryPeriod': 'hour', 'salaryCurrency': 'QAR'}).salaryLabel, 'QAR 30 / hour');
      expect(fakeJob('3', extra: {'city': 'Doha', 'state': 'Doha', 'country': 'Qatar'}).placeLabel, 'Doha, Qatar', reason: 'a repeated name is shown once');
    });

    test('details add sources; a job found twice lists both', () {
      final j = Job.fromJson({
        'id': 'x', 'title': 'T', 'companyName': 'C',
        'sources': [
          {'source': 'greenhouse', 'sourceJobId': '1', 'sourceUrl': 'https://a.test', 'missedChecks': 0},
          {'source': 'jooble', 'sourceJobId': '2', 'missedChecks': 1},
        ],
      });
      expect(j.sources.map((s) => s.source), ['greenhouse', 'jooble']);
      expect(j.sourceNames, ['greenhouse', 'jooble']);
      expect(j.sourceCount, 2);
    });

    test('copyWith changes triage state only', () {
      final j = fakeJob('1').copyWith(userState: 'saved', applicationStage: 'saved');
      expect(j.userState, 'saved');
      expect(j.title, 'Flutter Developer 1');
      expect(j.copyWith(clearStage: true).applicationStage, isNull);
      expect(thousands(1234567), '1,234,567');
      expect(humanize('full_time'), 'Full time');
    });
  });

  group('JobFilters', () {
    test('the quick views map to the API filters', () {
      expect(const JobFilters().toQuery(), {'status': 'active', 'sort': 'discovered'});
      expect(const JobFilters(view: JobView.newJobs).toQuery()['userState'], 'new');
      expect(const JobFilters(view: JobView.saved).toQuery(), {'userState': 'saved', 'sort': 'discovered'});
      expect(const JobFilters(view: JobView.expired).toQuery()['status'], 'expired');
      expect(const JobFilters(view: JobView.all).toQuery(), {'sort': 'discovered'});
    });

    test('only set filters are sent, trimmed', () {
      final q = const JobFilters(view: JobView.all, countryCode: 'US', city: ' Austin ', skills: ['Flutter', 'Dart'], salaryMin: 90000, salaryCurrency: 'USD', postedWithinDays: 7, query: '  ', sort: JobSort.posted).toQuery();
      expect(q, {'country': 'US', 'city': 'Austin', 'skills': 'Flutter,Dart', 'salaryMin': '90000', 'salaryCurrency': 'USD', 'postedWithinDays': '7', 'sort': 'posted'});
    });

    test('copyWith can clear a filter, and cleared() keeps view and sort', () {
      const f = JobFilters(view: JobView.saved, city: 'Austin', sort: JobSort.updated);
      expect(f.copyWith(city: null).city, isNull);
      expect(f.copyWith(view: JobView.all).city, 'Austin', reason: 'untouched fields stay');
      expect(f.cleared().view, JobView.saved);
      expect(f.cleared().sort, JobSort.updated);
      expect(f.cleared().hasExtraFilters, isFalse);
      expect(f.hasExtraFilters, isTrue);
    });
  });

  group('JobSearch', () {
    test('serialises the Country → State → City selection the way the API expects', () {
      const search = JobSearch(
        name: '  Flutter CA  ',
        countries: [
          JobCountrySelection(code: 'US', name: 'United States', level: JobSearchLevel.city, allRegions: false, regions: ['California'], allCities: false, cities: [JobCityPick('California', 'Los Angeles')], includeRemote: true),
          JobCountrySelection(code: 'DE', name: 'Germany', level: JobSearchLevel.state),
          JobCountrySelection(code: 'QA', name: 'Qatar', level: JobSearchLevel.country),
          JobCountrySelection(code: 'WW', name: 'Worldwide / Remote', level: JobSearchLevel.country),
        ],
        titles: ['Flutter Developer'],
        keywords: ['dart'],
        filters: JobSearchFilters(workArrangement: 'remote', salaryMin: 50000),
      );
      final j = search.toJson();
      expect(j['name'], 'Flutter CA');
      final countries = (j['countries'] as List).cast<Map<String, dynamic>>();
      expect(countries[0], {'code': 'US', 'level': 'city', 'regions': ['California'], 'cities': [{'state': 'California', 'city': 'Los Angeles'}], 'includeRemote': true});
      expect(countries[1], {'code': 'DE', 'level': 'state', 'regions': 'all', 'includeRemote': false});
      expect(countries[2], {'code': 'QA', 'level': 'country', 'includeRemote': false});
      expect(countries[3], {'code': 'WW'}, reason: 'worldwide has no levels');
      expect((j['filters'] as Map)['workArrangement'], 'remote');
    });

    test('round-trips through the API shape', () {
      final back = JobSearch.fromJson({
        'id': 's1', 'name': 'X', 'titles': ['A'], 'keywords': [], 'sources': ['adzuna'],
        'countries': [{'code': 'US', 'level': 'city', 'regions': 'all', 'cities': 'all', 'includeRemote': false}],
        'limits': {'concurrency': 5}, 'schedule': {'enabled': true, 'timeOfDay': '04:30', 'timezone': 'Asia/Qatar'},
      }, countryNames: {'US': 'United States'});
      expect(back.countries.single.name, 'United States');
      expect(back.countries.single.allRegions, isTrue);
      expect(back.countries.single.allCities, isTrue);
      expect(back.limits.concurrency, 5);
      expect(back.limits.maxCombinations, 20000);
      expect(back.schedule.enabled, isTrue);
      expect(back.schedule.timezone, 'Asia/Qatar');
    });

    test('a search is valid with a name, a country and a title', () {
      expect(const JobSearch().isValid, isFalse);
      expect(const JobSearch(name: 'ab', titles: ['x']).isValid, isFalse);
      expect(const JobSearch(name: 'ab', titles: ['x'], countries: [JobCountrySelection(code: 'US', name: 'US')]).isValid, isTrue);
    });
  });

  group('JobScan', () {
    test('reads live progress and knows what can be done', () {
      final s = JobScan.fromJson(scanJson('r1', done: 4, total: 10));
      expect(s.totals.finished, 4);
      expect(s.percent, 40);
      expect(s.canPause && s.canStop && !s.canResume, isTrue);
      expect(s.current.single.where, 'United States › California › Los Angeles');
      expect(s.sources.map((e) => e.id), ['greenhouse', 'adzuna']);
      expect(s.sources.last.stateLabel, 'Not configured');
      expect(JobScan.fromJson(scanJson('r', status: 'paused')).canResume, isTrue);
      expect(JobScan.fromJson(scanJson('r', status: 'interrupted')).canResume, isTrue);
      final done = JobScan.fromJson(scanJson('r', status: 'completed'));
      expect(done.isActive, isFalse);
      expect(done.canStop, isFalse);
      expect(done.elapsed, const Duration(minutes: 5));
    });
  });

  group('JobStats / sources / applications', () {
    test('stats', () {
      final s = JobStats.fromJson({
        'jobs': {'total': 10, 'active': 8, 'expired': 2, 'unseen': 5, 'discoveredLast24h': 3},
        'companies': 4,
        'applications': {'total': 2, 'byStage': {'saved': 1, 'interview': 1}},
        'scans': {'completed': 3, 'failed': 1, 'stopped': 0, 'successRate': 75},
      });
      expect(s.total, 10);
      expect(s.applicationsByStage[ApplicationStage.interview], 1);
      expect(s.applicationsByStage[ApplicationStage.offered], 0);
      expect(s.scansFinished, 4);
      expect(s.successRate, 75);
      expect(s.lastScan, isNull);
    });

    test('a source never carries a key — only whether one is set', () {
      final s = JobSourceInfo.fromJson({
        'id': 'adzuna', 'name': 'Adzuna', 'requiresKey': true, 'configured': false, 'configurationHint': 'Set ADZUNA_APP_ID',
        'limits': {'perMinute': 20, 'perDay': 250, 'maxConcurrent': 2}, 'usageToday': {'requests': 12, 'limit': 250},
        'settings': {'boards': [{'id': 'airbnb'}, 'stripe'], 'careerPages': [{'url': 'https://a.test/careers', 'company': 'A'}]},
        'status': {'consecutiveFailures': 2, 'lastError': {'message': 'HTTP 500'}},
      });
      expect(s.configured, isFalse);
      expect(s.requestsToday, 12);
      expect(s.boards, ['airbnb', 'stripe']);
      expect(s.careerPages.single.company, 'A');
      expect(s.lastError, 'HTTP 500');
    });

    test('applications and the stage order', () {
      expect(ApplicationStage.values.map((s) => s.label), ['Saved', 'Applied', 'Assessment', 'Interview', 'Offered', 'Rejected', 'Withdrawn']);
      final a = JobApplication.fromJson({'jobId': 'j', 'stage': 'interview', 'job': {'title': 'Dev', 'companyName': 'Co'}, 'notes': 'call Tue'});
      expect(a.stage, ApplicationStage.interview);
      expect(a.title, 'Dev');
      expect(a.copyWith(stage: ApplicationStage.offered).stage, ApplicationStage.offered);
      expect(ApplicationStage.parse('nope'), isNull);
    });

    test('alerts summarise their filters', () {
      expect(JobAlert.fromJson({'id': 'a', 'name': 'x', 'filters': {'q': 'flutter', 'workArrangement': 'remote', 'countryCode': 'QA'}}).summary, 'flutter · Remote · QA');
      expect(JobAlert.fromJson({'id': 'a', 'name': 'x'}).summary, 'Every new job');
    });
  });
}
