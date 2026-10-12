import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead_page.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart' show LeadDetailsArgs;
import 'lead_list_page.dart';

/// No-website leads — businesses a scan found with no website. This is the
/// big collection (tens of thousands), so it's only ever loaded a page at a
/// time: see [LeadListPage].
class WebsiteLeadsPage extends StatelessWidget {
  const WebsiteLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadListPage(
      config: LeadListConfig(
        collection: LeadCollection.websiteLeads,
        title: 'No-website leads',
        subtitleEmpty: 'Businesses found during a scan with no website will land here.',
        emptyTitle: 'No website leads yet',
        emptyBody: 'Run a scan — every business it finds with no website is saved here automatically.',
        emptyIcon: AppIcons.globe,
        searchHint: 'Search by name, phone, address or category',
        validationCollection: 'websiteLeads',
        emailFilter: true,
        cardBuilder: (context, lead, {required onTap, required onDelete, required deleting}) =>
            SavedBusinessCard(lead: lead, onTap: onTap, onDelete: onDelete, deleting: deleting),
        onOpen: (context, lead) =>
            context.push<bool>('/leads/details', extra: LeadDetailsArgs(lead: lead, isWebsiteLead: true)),
      ),
    );
  }
}
