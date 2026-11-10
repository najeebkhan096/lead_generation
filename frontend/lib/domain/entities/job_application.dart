import 'package:equatable/equatable.dart';

import 'job_json.dart';

/// The application pipeline, in order.
enum ApplicationStage {
  saved('saved', 'Saved'),
  applied('applied', 'Applied'),
  assessment('assessment', 'Assessment'),
  interview('interview', 'Interview'),
  offered('offered', 'Offered'),
  rejected('rejected', 'Rejected'),
  withdrawn('withdrawn', 'Withdrawn');

  const ApplicationStage(this.wire, this.label);
  final String wire;
  final String label;

  static ApplicationStage? parse(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return null;
  }
}

class JobApplication extends Equatable {
  const JobApplication({
    required this.jobId,
    required this.stage,
    this.title = '',
    this.companyName = '',
    this.locationText,
    this.sourceUrl,
    this.applyUrl,
    this.notes = '',
    this.contact,
    this.appliedAt,
    this.followUpAt,
    this.updatedAt,
  });

  factory JobApplication.fromJson(Map<String, dynamic> j) {
    final job = jobMap(j['job']);
    return JobApplication(
      jobId: jobString(j['jobId']) ?? jobString(j['id']) ?? '',
      stage: ApplicationStage.parse(j['stage']) ?? ApplicationStage.saved,
      title: jobString(job['title']) ?? 'Job',
      companyName: jobString(job['companyName']) ?? '',
      locationText: jobString(job['locationText']),
      sourceUrl: jobString(job['sourceUrl']),
      applyUrl: jobString(job['applyUrl']),
      notes: (j['notes'] as String?) ?? '',
      contact: jobString(j['contact']),
      appliedAt: jobDate(j['appliedAt']),
      followUpAt: jobDate(j['followUpAt']),
      updatedAt: jobDate(j['updatedAt']),
    );
  }

  final String jobId;
  final ApplicationStage stage;
  final String title;
  final String companyName;
  final String? locationText;
  final String? sourceUrl;
  final String? applyUrl;
  final String notes;
  final String? contact;
  final DateTime? appliedAt;
  final DateTime? followUpAt;
  final DateTime? updatedAt;

  JobApplication copyWith({ApplicationStage? stage, String? notes}) => JobApplication(
        jobId: jobId,
        stage: stage ?? this.stage,
        title: title,
        companyName: companyName,
        locationText: locationText,
        sourceUrl: sourceUrl,
        applyUrl: applyUrl,
        notes: notes ?? this.notes,
        contact: contact,
        appliedAt: appliedAt,
        followUpAt: followUpAt,
        updatedAt: updatedAt,
      );

  @override
  List<Object?> get props => [jobId, stage, notes, contact, appliedAt, followUpAt, updatedAt];
}
