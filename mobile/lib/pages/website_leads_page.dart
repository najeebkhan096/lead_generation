import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/paged_query.dart';
import '../theme/app_theme.dart';
import '../widgets/lead_collection_page.dart';
import '../widgets/verified_lead_card.dart';

/// The WhatsApp-validated **no-website** leads: businesses Google Maps lists
/// with no website (`websiteLeads`, `websiteStatus == 'missing'`) whose phone a
/// WhatsApp check confirmed (`hasWhatsApp == true`).
///
/// One live list, newest check first, with search and the category filter. It
/// is read-only: the daily limit and Contacted / Deal tracking are enforced
/// server-side for the 1-star review leads only, so this list has no such state.
class WebsiteLeadsPage extends StatelessWidget {
  const WebsiteLeadsPage({
    super.key,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  /// For tests: the query for a collection (default: Firestore's).
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;

  /// For tests: how WhatsApp / Maps are opened.
  final LeadActions actions;

  static const _collection = 'websiteLeads';

  Query<Map<String, dynamic>> _query(String? category) {
    Query<Map<String, dynamic>> q = (collectionQuery ?? FirebaseFirestore.instance.collection)(_collection)
        .where('hasWhatsApp', isEqualTo: true)
        .where('websiteStatus', isEqualTo: 'missing');
    if (category != null) q = q.where('category', isEqualTo: category);
    return q.orderBy('updatedAt', descending: true);
  }

  @override
  Widget build(BuildContext context) {
    return LeadCollectionPage<VerifiedLead>(
      title: 'WhatsApp · no website',
      noun: 'business',
      headerIcon: AppIcons.globe,
      // The size of the pool stays on the web console, not on the salesman's phone.
      showCounts: false,
      searchHint: 'Search no-website leads...',
      emptyIcon: AppIcons.globe,
      emptyTitle: 'No validated no-website leads yet',
      emptyBody: 'Businesses with no website whose WhatsApp number is confirmed appear here.',
      emptySubtitle: 'Validated leads will land here',
      controllerFor: (_) => PagedQueryController<VerifiedLead>(
        segments: [_query],
        map: (doc) => VerifiedLead.fromData(Lead.fromDoc(doc), doc.data()),
      ),
      dateOf: (row) => row.shownDate,
      searchText: (r) => '${r.lead.business} ${r.lead.location} ${r.lead.phone ?? ''} ${r.lead.category}'.toLowerCase(),
      categoryOf: (r) => r.lead.category,
      itemBuilder: (context, row) => VerifiedLeadCard(
        key: ValueKey(row.lead.id),
        item: row,
        actions: actions,
      ),
    );
  }
}
