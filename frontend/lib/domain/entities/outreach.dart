import 'package:equatable/equatable.dart';

enum OutreachStatus {
  notProcessed,
  emailFound,
  emailVerified,
  emailInvalid,
  readyForReview,
  approved,
  queued,
  sent,
  delivered,
  opened,
  replied,
  interested,
  notInterested,
  bounced,
  unsubscribed,
  failed,
  paused;

  static OutreachStatus fromJson(String? value) {
    return switch (value) {
      'email_found' => OutreachStatus.emailFound,
      'email_verified' => OutreachStatus.emailVerified,
      'email_invalid' => OutreachStatus.emailInvalid,
      'ready_for_review' => OutreachStatus.readyForReview,
      'approved' => OutreachStatus.approved,
      'queued' => OutreachStatus.queued,
      'sent' => OutreachStatus.sent,
      'delivered' => OutreachStatus.delivered,
      'opened' => OutreachStatus.opened,
      'replied' => OutreachStatus.replied,
      'interested' => OutreachStatus.interested,
      'not_interested' => OutreachStatus.notInterested,
      'bounced' => OutreachStatus.bounced,
      'unsubscribed' => OutreachStatus.unsubscribed,
      'failed' => OutreachStatus.failed,
      'paused' => OutreachStatus.paused,
      _ => OutreachStatus.notProcessed,
    };
  }

  String get json => switch (this) {
        OutreachStatus.notProcessed => 'not_processed',
        OutreachStatus.emailFound => 'email_found',
        OutreachStatus.emailVerified => 'email_verified',
        OutreachStatus.emailInvalid => 'email_invalid',
        OutreachStatus.readyForReview => 'ready_for_review',
        OutreachStatus.approved => 'approved',
        OutreachStatus.queued => 'queued',
        OutreachStatus.sent => 'sent',
        OutreachStatus.delivered => 'delivered',
        OutreachStatus.opened => 'opened',
        OutreachStatus.replied => 'replied',
        OutreachStatus.interested => 'interested',
        OutreachStatus.notInterested => 'not_interested',
        OutreachStatus.bounced => 'bounced',
        OutreachStatus.unsubscribed => 'unsubscribed',
        OutreachStatus.failed => 'failed',
        OutreachStatus.paused => 'paused',
      };

  String get label => switch (this) {
        OutreachStatus.notProcessed => 'Not sent',
        OutreachStatus.emailFound => 'Email found · not sent',
        OutreachStatus.emailVerified => 'Email ready · not sent',
        OutreachStatus.emailInvalid => 'No email',
        OutreachStatus.readyForReview => 'Draft ready · not sent',
        OutreachStatus.approved => 'Approved · not sent',
        OutreachStatus.queued => 'Sending',
        OutreachStatus.sent => 'Sent',
        OutreachStatus.delivered => 'Sent',
        OutreachStatus.opened => 'Opened',
        OutreachStatus.replied => 'Replied',
        OutreachStatus.interested => 'Interested',
        OutreachStatus.notInterested => 'Skipped',
        OutreachStatus.bounced => 'Bounced',
        OutreachStatus.unsubscribed => 'Unsubscribed',
        OutreachStatus.failed => 'Send failed',
        OutreachStatus.paused => 'Paused',
      };

  bool get wasSent => switch (this) {
        OutreachStatus.sent ||
        OutreachStatus.delivered ||
        OutreachStatus.opened ||
        OutreachStatus.replied ||
        OutreachStatus.interested =>
          true,
        _ => false,
      };

  String get sendLabel => switch (this) {
        OutreachStatus.queued => 'Sending',
        OutreachStatus.sent || OutreachStatus.delivered => 'Sent',
        OutreachStatus.opened => 'Opened',
        OutreachStatus.replied => 'Replied',
        OutreachStatus.interested => 'Interested',
        OutreachStatus.failed || OutreachStatus.bounced => 'Failed',
        OutreachStatus.emailInvalid => 'No email',
        OutreachStatus.unsubscribed => 'Unsubscribed',
        OutreachStatus.notInterested || OutreachStatus.paused => 'Skipped',
        _ => 'Not sent',
      };
}

class OutreachObservation extends Equatable {
  const OutreachObservation({required this.title, required this.description, this.evidence});

  final String title;
  final String description;
  final String? evidence;

  factory OutreachObservation.fromJson(Map<String, dynamic> json) {
    return OutreachObservation(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      evidence: json['evidence'] as String?,
    );
  }

  @override
  List<Object?> get props => [title, description, evidence];
}

class WebsiteAnalysis extends Equatable {
  const WebsiteAnalysis({
    required this.score,
    required this.issues,
    required this.opportunities,
    this.skipped = false,
    this.reason,
  });

  final int score;
  final List<OutreachObservation> issues;
  final List<OutreachObservation> opportunities;
  final bool skipped;
  final String? reason;

  factory WebsiteAnalysis.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const WebsiteAnalysis(score: 0, issues: [], opportunities: []);
    }
    List<OutreachObservation> list(dynamic raw) {
      return (raw as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => OutreachObservation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return WebsiteAnalysis(
      score: (json['score'] as num?)?.toInt() ?? 0,
      issues: list(json['issues']),
      opportunities: list(json['opportunities']),
      skipped: json['skipped'] == true,
      reason: json['reason'] as String?,
    );
  }

  @override
  List<Object?> get props => [score, issues, opportunities, skipped];
}

class OutreachRecord extends Equatable {
  const OutreachRecord({
    required this.id,
    required this.sourceCollection,
    required this.sourceLeadId,
    this.campaignId,
    required this.business,
    this.category,
    this.location,
    this.website,
    this.email,
    this.emailStatus,
    this.emailSource,
    this.emailVerified = false,
    this.outreachStatus = OutreachStatus.notProcessed,
    this.websiteAnalysisStatus,
    this.emailGenerationStatus,
    this.outreachApproved = false,
    this.websiteAnalysis,
    this.generatedSubject,
    this.generatedBody,
    this.generatedAt,
    this.aiModel,
    this.lastContactedAt,
    this.followUpCount = 0,
    this.nextFollowUpAt,
    this.unsubscribeStatus = false,
    this.lastError,
  });

  final String id;
  final String sourceCollection;
  final String sourceLeadId;
  final String? campaignId;
  final String business;
  final String? category;
  final String? location;
  final String? website;
  final String? email;
  final String? emailStatus;
  final String? emailSource;
  final bool emailVerified;
  final OutreachStatus outreachStatus;
  final String? websiteAnalysisStatus;
  final String? emailGenerationStatus;
  final bool outreachApproved;
  final WebsiteAnalysis? websiteAnalysis;
  final String? generatedSubject;
  final String? generatedBody;
  final DateTime? generatedAt;
  final String? aiModel;
  final DateTime? lastContactedAt;
  final int followUpCount;
  final DateTime? nextFollowUpAt;
  final bool unsubscribeStatus;
  final String? lastError;

  factory OutreachRecord.fromJson(Map<String, dynamic> json) {
    return OutreachRecord(
      id: json['id'] as String? ?? '',
      sourceCollection: json['sourceCollection'] as String? ?? 'websiteLeads',
      sourceLeadId: json['sourceLeadId'] as String? ?? '',
      campaignId: json['campaignId'] as String?,
      business: json['business'] as String? ?? '',
      category: json['category'] as String?,
      location: json['location'] as String?,
      website: json['website'] as String?,
      email: json['email'] as String?,
      emailStatus: json['emailStatus'] as String?,
      emailSource: json['emailSource'] as String?,
      emailVerified: json['emailVerified'] == true,
      outreachStatus: OutreachStatus.fromJson(json['outreachStatus'] as String?),
      websiteAnalysisStatus: json['websiteAnalysisStatus'] as String?,
      emailGenerationStatus: json['emailGenerationStatus'] as String?,
      outreachApproved: json['outreachApproved'] == true,
      websiteAnalysis: json['websiteAnalysis'] is Map
          ? WebsiteAnalysis.fromJson(Map<String, dynamic>.from(json['websiteAnalysis'] as Map))
          : null,
      generatedSubject: json['generatedSubject'] as String?,
      generatedBody: json['generatedBody'] as String?,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      aiModel: json['aiModel'] as String?,
      lastContactedAt: DateTime.tryParse(json['lastContactedAt'] as String? ?? ''),
      followUpCount: (json['followUpCount'] as num?)?.toInt() ?? 0,
      nextFollowUpAt: DateTime.tryParse(json['nextFollowUpAt'] as String? ?? ''),
      unsubscribeStatus: json['unsubscribeStatus'] == true,
      lastError: json['lastError'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, business, outreachStatus, email, outreachApproved];
}

class OutreachCampaign extends Equatable {
  const OutreachCampaign({
    required this.id,
    required this.name,
    this.description = '',
    this.status = 'draft',
    this.sourceCollection = 'websiteLeads',
    this.dailyLimit = 30,
    this.followUpEnabled = true,
    this.followUp1DelayDays = 3,
    this.followUp2DelayDays = 4,
    this.testMode = false,
    this.filters = const {},
    this.stats = const {},
  });

  final String id;
  final String name;
  final String description;
  final String status;
  final String sourceCollection;
  final int dailyLimit;
  final bool followUpEnabled;
  final int followUp1DelayDays;
  final int followUp2DelayDays;
  final bool testMode;
  final Map<String, dynamic> filters;
  final Map<String, dynamic> stats;

  factory OutreachCampaign.fromJson(Map<String, dynamic> json) {
    return OutreachCampaign(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'draft',
      sourceCollection: json['sourceCollection'] as String? ?? 'websiteLeads',
      dailyLimit: (json['dailyLimit'] as num?)?.toInt() ?? 30,
      followUpEnabled: json['followUpEnabled'] != false,
      followUp1DelayDays: (json['followUp1DelayDays'] as num?)?.toInt() ?? 3,
      followUp2DelayDays: (json['followUp2DelayDays'] as num?)?.toInt() ?? 4,
      testMode: json['testMode'] == true,
      filters: Map<String, dynamic>.from(json['filters'] as Map? ?? const {}),
      stats: Map<String, dynamic>.from(json['stats'] as Map? ?? const {}),
    );
  }

  int get statLeads => (stats['leads'] as num?)?.toInt() ?? 0;
  int get statApproved => (stats['approved'] as num?)?.toInt() ?? 0;
  int get statSent => (stats['sent'] as num?)?.toInt() ?? 0;
  int get statReplies => (stats['replies'] as num?)?.toInt() ?? 0;
  int get statInterested => (stats['interested'] as num?)?.toInt() ?? 0;

  @override
  List<Object?> get props => [id, name, status];
}

class OutreachSettings extends Equatable {
  const OutreachSettings({
    this.testMode = false,
    this.testEmail = '',
    this.senderName = 'Najeeb',
    this.senderEmail = '',
    this.replyTo = '',
    this.defaultDailyLimit = 30,
    this.senderConfigured = false,
  });

  final bool testMode;
  final String testEmail;
  final String senderName;
  final String senderEmail;
  final String replyTo;
  final int defaultDailyLimit;
  final bool senderConfigured;

  factory OutreachSettings.fromJson(Map<String, dynamic>? json) {
    final d = json ?? const {};
    return OutreachSettings(
      testMode: d['testMode'] == true,
      testEmail: d['testEmail'] as String? ?? '',
      senderName: d['senderName'] as String? ?? 'Najeeb',
      senderEmail: d['senderEmail'] as String? ?? '',
      replyTo: d['replyTo'] as String? ?? '',
      defaultDailyLimit: (d['defaultDailyLimit'] as num?)?.toInt() ?? 30,
      senderConfigured: d['senderConfigured'] == true,
    );
  }

  @override
  List<Object?> get props => [testMode, testEmail, senderName, senderEmail, senderConfigured];
}

class OutreachStats extends Equatable {
  const OutreachStats({
    this.totalWebsiteLeads = 0,
    this.totalRecords = 0,
    this.emailsFound = 0,
    this.verifiedEmails = 0,
    this.readyForReview = 0,
    this.approved = 0,
    this.queued = 0,
    this.sent = 0,
    this.delivered = 0,
    this.opened = 0,
    this.replies = 0,
    this.interested = 0,
    this.bounced = 0,
    this.unsubscribed = 0,
    this.failed = 0,
  });

  final int totalWebsiteLeads;
  final int totalRecords;
  final int emailsFound;
  final int verifiedEmails;
  final int readyForReview;
  final int approved;
  final int queued;
  final int sent;
  final int delivered;
  final int opened;
  final int replies;
  final int interested;
  final int bounced;
  final int unsubscribed;
  final int failed;

  factory OutreachStats.fromJson(Map<String, dynamic>? json) {
    final d = json ?? const {};
    int n(String k) => (d[k] as num?)?.toInt() ?? 0;
    return OutreachStats(
      totalWebsiteLeads: n('totalWebsiteLeads'),
      totalRecords: n('totalRecords'),
      emailsFound: n('emailsFound'),
      verifiedEmails: n('verifiedEmails'),
      readyForReview: n('readyForReview'),
      approved: n('approved'),
      queued: n('queued'),
      sent: n('sent'),
      delivered: n('delivered'),
      opened: n('opened'),
      replies: n('replies'),
      interested: n('interested'),
      bounced: n('bounced'),
      unsubscribed: n('unsubscribed'),
      failed: n('failed'),
    );
  }

  @override
  List<Object?> get props => [totalRecords, sent, replies];
}

class OutreachJob extends Equatable {
  const OutreachJob({
    this.status = 'idle',
    this.kind,
    this.from,
    this.to,
    this.total = 0,
    this.processed = 0,
    this.failed = 0,
    this.skipped = 0,
    this.emailsFound = 0,
    this.verified = 0,
    this.queued = 0,
    this.currentBusiness,
  });

  final String status;
  final String? kind;
  final int? from;
  final int? to;
  final int total;
  final int processed;
  final int failed;
  final int skipped;
  final int emailsFound;
  final int verified;
  final int queued;
  final String? currentBusiness;

  bool get isRunning => status == 'running';

  factory OutreachJob.fromJson(Map<String, dynamic>? json) {
    final d = json ?? const {};
    int n(String k) => (d[k] as num?)?.toInt() ?? 0;
    final current = d['current'];
    return OutreachJob(
      status: d['status'] as String? ?? 'idle',
      kind: d['kind'] as String?,
      from: (d['from'] as num?)?.toInt(),
      to: (d['to'] as num?)?.toInt(),
      total: n('total'),
      processed: n('processed'),
      failed: n('failed'),
      skipped: n('skipped'),
      emailsFound: n('emailsFound'),
      verified: n('verified'),
      queued: n('queued'),
      currentBusiness: current is Map ? current['business'] as String? : null,
    );
  }

  @override
  List<Object?> get props => [status, kind, processed, total];
}

class OutreachDashboard extends Equatable {
  const OutreachDashboard({
    required this.stats,
    required this.settings,
    this.campaigns = const [],
    this.job = const OutreachJob(),
  });

  final OutreachStats stats;
  final OutreachSettings settings;
  final List<OutreachCampaign> campaigns;
  final OutreachJob job;

  factory OutreachDashboard.fromJson(Map<String, dynamic> json) {
    return OutreachDashboard(
      stats: OutreachStats.fromJson(json['stats'] as Map<String, dynamic>?),
      settings: OutreachSettings.fromJson(json['settings'] as Map<String, dynamic>?),
      campaigns: (json['campaigns'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => OutreachCampaign.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      job: OutreachJob.fromJson(json['job'] as Map<String, dynamic>?),
    );
  }

  OutreachDashboard copyWith({OutreachSettings? settings, OutreachJob? job, OutreachStats? stats}) {
    return OutreachDashboard(
      stats: stats ?? this.stats,
      settings: settings ?? this.settings,
      campaigns: campaigns,
      job: job ?? this.job,
    );
  }

  @override
  List<Object?> get props => [stats, settings, campaigns, job];
}

class OutreachAnalytics extends Equatable {
  const OutreachAnalytics({
    required this.stats,
    required this.rates,
    required this.campaigns,
    this.testMode = false,
  });

  final OutreachStats stats;
  final Map<String, double> rates;
  final List<OutreachCampaign> campaigns;
  final bool testMode;

  factory OutreachAnalytics.fromJson(Map<String, dynamic> json) {
    final rawRates = json['rates'] as Map<String, dynamic>? ?? const {};
    return OutreachAnalytics(
      stats: OutreachStats.fromJson(json['stats'] as Map<String, dynamic>?),
      rates: {
        for (final e in rawRates.entries) e.key: (e.value as num?)?.toDouble() ?? 0,
      },
      campaigns: (json['campaigns'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => OutreachCampaign.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      testMode: json['testMode'] == true,
    );
  }

  @override
  List<Object?> get props => [stats, rates, campaigns];
}

class OutreachEvent extends Equatable {
  const OutreachEvent({required this.id, required this.type, this.message, this.createdAt});

  final String id;
  final String type;
  final String? message;
  final DateTime? createdAt;

  factory OutreachEvent.fromJson(Map<String, dynamic> json) {
    return OutreachEvent(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      message: json['message'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }

  String get label => type.replaceAll('_', ' ');

  @override
  List<Object?> get props => [id, type];
}
