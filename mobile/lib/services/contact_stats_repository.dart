import 'package:cloud_firestore/cloud_firestore.dart';

import 'daily_contact_repository.dart';

/// The two kinds of lead a salesman contacts. One daily limit covers both.
enum ContactKind {
  /// 1-star review leads (`whatsappLeads`, review kind).
  review('whatsappLeads'),

  /// No-website leads (`websiteLeads`).
  website('websiteLeads');

  const ContactKind(this.collection);
  final String collection;
}

/// New leads contacted today, in the last 7 days and in total — of one kind.
class ContactCounts {
  const ContactCounts({this.today = 0, this.last7 = 0, this.total = 0});

  final int today;
  final int last7;
  final int total;
}

/// One lead a salesman contacted, for the recent list.
class ContactedItem {
  const ContactedItem({
    required this.id,
    required this.kind,
    required this.business,
    this.category = '',
    this.location = '',
    this.phone,
    this.contactedAt,
    this.status = 'contacted',
  });

  final String id;
  final ContactKind kind;
  final String business;
  final String category;
  final String location;
  final String? phone;
  final DateTime? contactedAt;

  /// `contacted`, or `dealDone` for a 1-star lead the salesman closed.
  final String status;

  factory ContactedItem.fromDoc(ContactKind kind, String id, Map<String, dynamic> data) {
    final at = data['contactedAt'];
    return ContactedItem(
      id: id,
      kind: kind,
      business: (data['business'] as String?)?.trim().isNotEmpty == true ? data['business'] as String : 'Unnamed',
      category: (data['category'] as String?) ?? '',
      location: (data['location'] as String?) ?? '',
      phone: data['phone'] as String?,
      contactedAt: at is Timestamp ? at.toDate() : null,
      status: (data['status'] as String?) ?? 'contacted',
    );
  }
}

/// A salesman's contact record, as the admin sees it.
class ContactStats {
  const ContactStats({this.review = const ContactCounts(), this.website = const ContactCounts(), this.recent = const []});

  final ContactCounts review;
  final ContactCounts website;

  /// The latest contacts of both kinds, newest first.
  final List<ContactedItem> recent;

  /// Today, last 7 days and total across both kinds — what the daily limit counts.
  int get today => review.today + website.today;
  int get last7 => review.last7 + website.last7;
  int get total => review.total + website.total;
}

/// Reads one salesman's contacts straight from Firestore (the admin console on
/// the phone has no backend): 1-star and no-website leads, counted separately
/// and together.
///
/// Counts are server-side aggregations, so a salesman with thousands of
/// contacts costs a handful of reads, not thousands. Days are the business day,
/// Asia/Qatar, the same one the limit uses.
class ContactStatsRepository {
  ContactStatsRepository({Query<Map<String, dynamic>> Function(String collection)? collectionQuery, DateTime Function()? clock})
      : _collectionQuery = collectionQuery,
        _clock = clock ?? DateTime.now;

  final Query<Map<String, dynamic>> Function(String collection)? _collectionQuery;
  final DateTime Function() _clock;

  /// How many recent contacts of each kind are read.
  static const recentPerKind = 15;

  /// How many of the merged recent contacts are shown.
  static const recentShown = 20;

  Query<Map<String, dynamic>> _mine(ContactKind kind, String uid) {
    Query<Map<String, dynamic>> q = (_collectionQuery ?? FirebaseFirestore.instance.collection)(kind.collection);
    if (kind == ContactKind.review) q = q.where('sourceType', isEqualTo: 'review');
    return q.where('contactedBy', isEqualTo: uid);
  }

  Future<int> _count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;

  Future<ContactCounts> _countsFor(ContactKind kind, String uid, Timestamp todayStart, Timestamp weekStart) async {
    final mine = _mine(kind, uid);
    final counts = await Future.wait([
      _count(mine.where('contactedAt', isGreaterThanOrEqualTo: todayStart)),
      _count(mine.where('contactedAt', isGreaterThanOrEqualTo: weekStart)),
      _count(mine),
    ]);
    return ContactCounts(today: counts[0], last7: counts[1], total: counts[2]);
  }

  Future<List<ContactedItem>> _recentFor(ContactKind kind, String uid) async {
    final snap = await _mine(kind, uid).orderBy('contactedAt', descending: true).limit(recentPerKind).get();
    return [for (final doc in snap.docs) ContactedItem.fromDoc(kind, doc.id, doc.data())];
  }

  Future<ContactStats> load(String uid) async {
    final now = _clock();
    final todayStart = Timestamp.fromDate(dailyDayStart(dailyDayKey(now)));
    // "Last 7 days" is today and the six before it.
    final weekStart = Timestamp.fromDate(dailyDayStart(dailyDayKey(now.subtract(const Duration(days: 6)))));
    final results = await Future.wait([
      _countsFor(ContactKind.review, uid, todayStart, weekStart),
      _countsFor(ContactKind.website, uid, todayStart, weekStart),
      _recentFor(ContactKind.review, uid),
      _recentFor(ContactKind.website, uid),
    ]);
    final recent = [...(results[2] as List<ContactedItem>), ...(results[3] as List<ContactedItem>)]
      ..sort((a, b) => (b.contactedAt ?? DateTime(0)).compareTo(a.contactedAt ?? DateTime(0)));
    return ContactStats(
      review: results[0] as ContactCounts,
      website: results[1] as ContactCounts,
      recent: recent.take(recentShown).toList(),
    );
  }
}
