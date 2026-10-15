import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/paged_query.dart';
import '../theme/app_theme.dart';
import '../utils/seeded_shuffle.dart';
import '../widgets/lead_collection_page.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

// Other screens reuse the empty-state badge from here.
export '../widgets/lead_collection_page.dart' show StateBadge;

/// "Discover leads" — the 1-star review leads nobody has worked yet.
///
/// Paged, not streamed: the collection is read a page at a time and the
/// next page is fetched as you scroll (see [LeadCollectionPage]).
///
/// Two orders (the chips under the search box):
///
///  * **Newest** (default) — by the date the lead was found, grouped under
///    "Today", "Yesterday", ... so fresh leads are obvious.
///  * **My queue** — every salesman shares this one pool, and newest-first
///    puts everyone onto the same businesses. So this order starts at a
///    point derived from the salesman's uid in the (uniformly spread)
///    document-id order and wraps around — different salesmen work through
///    different parts of the pool, without downloading it all to shuffle it.
class SavedBusinessesPage extends StatelessWidget {
  const SavedBusinessesPage({super.key});

  static const _queue = 'queue';

  /// Newest first by `createdAt` (when the scan found it — `updatedAt` also
  /// moves on every re-scan and status change, so it can't mean "new").
  static List<SegmentQuery> _newest() => [
        (category) {
          Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('leads');
          if (category != null) q = q.where('category', isEqualTo: category);
          return q.orderBy('createdAt', descending: true);
        },
      ];

  static List<SegmentQuery> _segments(String? salesmanId) {
    Query<Map<String, dynamic>> base(String? category) {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('leads');
      if (category != null) q = q.where('category', isEqualTo: category);
      return q.orderBy(FieldPath.documentId);
    }

    if (salesmanId == null || salesmanId.isEmpty) return [base];
    final start = seededStartId(salesmanId);
    return [
      (category) => base(category).startAt([start]),
      (category) => base(category).endBefore([start]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final salesmanId = FirebaseAuth.instance.currentUser?.uid;
    return LeadCollectionPage<Lead>(
      title: 'Discover leads',
      noun: 'business',
      headerIcon: AppIcons.sparkles,
      searchHint: 'Search leads...',
      emptyIcon: AppIcons.inbox,
      emptyTitle: 'No businesses saved yet',
      emptyBody: 'Run a search in the LeadFinder web console — businesses with a recent 1-star review land here.',
      emptySubtitle: 'New businesses will land here',
      filters: const [
        (label: 'Newest', value: null),
        (label: 'My queue', value: _queue),
      ],
      dateOf: (lead) => lead.dateAdded,
      groupWhen: (filter) => filter != _queue,
      controllerFor: (filter) => PagedQueryController<Lead>(
        segments: filter == _queue ? _segments(salesmanId) : _newest(),
        map: Lead.fromDoc,
        // Only leads nobody has started working ("New"). `status` is unset
        // on most documents, which Firestore can't filter for, so it's
        // checked here.
        include: (lead) => lead.status == LeadStatus.lead,
      ),
      searchText: (l) => '${l.business} ${l.location} ${l.phone ?? ''} ${l.category}'.toLowerCase(),
      categoryOf: (l) => l.category,
      itemBuilder: (context, lead) => SavedBusinessCard(
        lead: lead,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BusinessDetailsPage(lead: lead)),
        ),
      ),
    );
  }
}
