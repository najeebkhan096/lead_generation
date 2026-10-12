import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../services/paged_query.dart';
import '../services/website_lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/lead_collection_page.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

/// Businesses a scan found with no website at all (`websiteLeads`).
///
/// This is the big collection — tens of thousands of documents — so it is
/// only ever read a page at a time, newest first, with the next page
/// fetched as you scroll (see [LeadCollectionPage]).
class WebsiteLeadsPage extends StatelessWidget {
  const WebsiteLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = WebsiteLeadRepository();
    return LeadCollectionPage<Lead>(
      title: 'Website leads',
      noun: 'business',
      headerIcon: AppIcons.globe,
      searchHint: 'Search website leads...',
      emptyIcon: AppIcons.globe,
      emptyTitle: 'No website leads yet',
      emptyBody: 'Businesses a scan finds with no website land here.',
      emptySubtitle: 'Businesses found with no website will land here',
      controllerFor: (_) => PagedQueryController<Lead>(
        segments: [
          (category) {
            Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('websiteLeads');
            if (category != null) q = q.where('category', isEqualTo: category);
            return q.orderBy('updatedAt', descending: true);
          },
        ],
        map: Lead.fromDoc,
      ),
      searchText: (l) => '${l.business} ${l.location} ${l.phone ?? ''} ${l.category}'.toLowerCase(),
      categoryOf: (l) => l.category,
      // One document per scan batch — far cheaper than reading the leads.
      loadCategories: LeadRepository().fetchCategoryNames,
      itemBuilder: (context, lead) => SavedBusinessCard(
        lead: lead,
        showWhatsAppAction: false,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BusinessDetailsPage(
              lead: lead,
              updateStatus: repo.updateStatus,
              isWebsiteLead: true,
            ),
          ),
        ),
      ),
    );
  }
}
