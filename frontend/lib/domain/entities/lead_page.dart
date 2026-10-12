import 'package:equatable/equatable.dart';

import 'lead.dart';

/// The lead collections the backend can list a page of.
enum LeadCollection {
  /// 1-star review leads (`leads`).
  reviewLeads('leads', '/api/db/leads'),

  /// Businesses with no website (`websiteLeads`).
  websiteLeads('websiteLeads', '/api/db/website-leads'),

  /// Numbers confirmed on WhatsApp (`whatsappLeads`).
  whatsappLeads('whatsappLeads', '/api/db/whatsapp-leads'),

  /// Verified contact emails (`emailLeads`).
  emailLeads('emailLeads', '/api/db/email-leads');

  const LeadCollection(this.firestoreName, this.path);

  /// The Firestore collection name — what `/api/db/categories` and the
  /// validators call it.
  final String firestoreName;

  /// The list endpoint.
  final String path;
}

/// One page of a lead list. [nextCursor] is `null` on the last page;
/// [total] is the number of leads matching the filters when the backend
/// knows it (first page of an indexed query) and `null` otherwise — notably
/// while a text search is scanning.
class LeadPage extends Equatable {
  const LeadPage({required this.leads, this.nextCursor, this.total, this.scanned});

  final List<Lead> leads;
  final String? nextCursor;
  final int? total;

  /// How many documents a search scanned to produce this page (search only).
  final int? scanned;

  bool get hasMore => nextCursor != null;

  factory LeadPage.fromJson(Map<String, dynamic> json) {
    return LeadPage(
      leads: ((json['leads'] as List<dynamic>?) ?? const [])
          .map((e) => Lead.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      total: (json['total'] as num?)?.toInt(),
      scanned: (json['scanned'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [leads, nextCursor, total, scanned];
}

/// A category and how many leads are in it.
class LeadCategory extends Equatable {
  const LeadCategory({required this.name, required this.count});

  final String name;
  final int count;

  factory LeadCategory.fromJson(Map<String, dynamic> json) => LeadCategory(
        name: (json['name'] as String?) ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [name, count];
}

/// The dashboard's numbers, computed by the backend so the browser never
/// downloads the leads just to count them.
class DashboardOverview extends Equatable {
  const DashboardOverview({
    required this.total,
    required this.whatsAppReady,
    required this.categories,
    required this.markets,
    required this.avgRating,
    required this.addedThisWeek,
    required this.topCategories,
    required this.recent,
    required this.reviewLeads,
    required this.websiteLeads,
    required this.whatsappLeads,
    required this.emailLeads,
  });

  final int total;
  final int whatsAppReady;
  final int categories;
  final int markets;
  final double? avgRating;
  final int addedThisWeek;
  final List<LeadCategory> topCategories;
  final List<Lead> recent;

  /// Collection sizes.
  final int reviewLeads;
  final int websiteLeads;
  final int whatsappLeads;
  final int emailLeads;

  bool get isEmpty => reviewLeads == 0 && websiteLeads == 0;

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    final review = (json['review'] as Map<String, dynamic>?) ?? const {};
    final counts = (json['counts'] as Map<String, dynamic>?) ?? const {};
    int n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;
    return DashboardOverview(
      total: n(review, 'total'),
      whatsAppReady: n(review, 'whatsAppReady'),
      categories: n(review, 'categories'),
      markets: n(review, 'markets'),
      avgRating: (review['avgRating'] as num?)?.toDouble(),
      addedThisWeek: n(review, 'addedThisWeek'),
      topCategories: ((review['topCategories'] as List<dynamic>?) ?? const [])
          .map((e) => LeadCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      recent: ((json['recent'] as List<dynamic>?) ?? const [])
          .map((e) => Lead.fromJson(e as Map<String, dynamic>))
          .toList(),
      reviewLeads: n(counts, 'reviewLeads'),
      websiteLeads: n(counts, 'websiteLeads'),
      whatsappLeads: n(counts, 'whatsappLeads'),
      emailLeads: n(counts, 'emailLeads'),
    );
  }

  @override
  List<Object?> get props => [total, reviewLeads, websiteLeads, whatsappLeads, emailLeads, recent];
}
