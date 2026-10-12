import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
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
/// Every salesman shares this one pool, and newest-first would put everyone
/// onto the same businesses. So each salesman's reading starts at a point
/// derived from their uid in the (uniformly spread) document-id order and
/// wraps around — different salesmen work through different parts of the
/// pool, without anyone downloading all of it to shuffle it.
class SavedBusinessesPage extends StatelessWidget {
  const SavedBusinessesPage({super.key});

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
    final repo = LeadRepository();
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
      controllerFor: (_) => PagedQueryController<Lead>(
        segments: _segments(salesmanId),
        map: Lead.fromDoc,
        // Only leads nobody has started working ("New"). `status` is unset
        // on most documents, which Firestore can't filter for, so it's
        // checked here.
        include: (lead) => lead.status == LeadStatus.lead,
      ),
      searchText: (l) => '${l.business} ${l.location} ${l.phone ?? ''} ${l.category}'.toLowerCase(),
      categoryOf: (l) => l.category,
      loadCategories: repo.fetchCategoryNames,
      itemBuilder: (context, lead) => SavedBusinessCard(
        lead: lead,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BusinessDetailsPage(lead: lead)),
        ),
      ),
    );
  }
}
