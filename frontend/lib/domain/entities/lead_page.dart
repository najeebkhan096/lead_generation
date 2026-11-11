import 'package:equatable/equatable.dart';

import 'lead.dart';

/// The lead lists the backend can page through. The 1-star scans and the
/// no-website scans are different things, so each has its own lists: a no-website
/// list never includes the no-website businesses a 1-star scan filed on the side
/// (the backend scopes it with [query]'s `scan=no_website`).
enum LeadCollection {
  /// 1-star review leads (`leads`).
  reviewLeads('leads', '/api/db/leads'),

  /// Numbers confirmed on WhatsApp (`whatsappLeads`).
  whatsappLeads('whatsappLeads', '/api/db/whatsapp-leads'),

  /// Numbers confirmed on WhatsApp for the 1-star review leads only.
  whatsappReviewLeads('whatsappLeads', '/api/db/whatsapp-leads', {'sourceType': 'review'}),

  /// Businesses confirmed to have no website, found by a no-website scan
  /// (`websiteLeads`).
  websiteLeads('websiteLeads', '/api/db/website-leads', {'scan': 'no_website'}),

  /// The no-website leads whose number a WhatsApp check confirmed.
  websiteVerified('websiteLeads', '/api/db/website-leads', {'scan': 'no_website', 'verified': '1'}),

  /// The no-website leads an email lookup found an address for.
  websiteWithEmail('websiteLeads', '/api/db/website-leads', {'scan': 'no_website', 'email': '1'}),

  /// Businesses whose website publishes a business email (`emailLeads`).
  emailLeads('emailLeads', '/api/db/email-leads');

  const LeadCollection(this.firestoreName, this.path, [this.query = const {}]);

  /// The Firestore collection name — what `/api/db/categories` and the
  /// validators call it.
  final String firestoreName;

  /// The list endpoint.
  final String path;

  /// Fixed query parameters that narrow the list (sent with the page and the
  /// category requests alike, so the categories match the list).
  final Map<String, String> query;
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
    required this.whatsappLeads,
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
  final int whatsappLeads;

  bool get isEmpty => reviewLeads == 0;

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
      whatsappLeads: n(counts, 'whatsappLeads'),
    );
  }

  @override
  List<Object?> get props => [total, reviewLeads, whatsappLeads, recent];
}
