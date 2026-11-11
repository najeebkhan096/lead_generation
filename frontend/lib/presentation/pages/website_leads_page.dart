import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/lead_page.dart';
import '../design_system/design_system.dart';
import '../widgets/site_lead_card.dart';
import 'lead_list_page.dart';
import '../widgets/lead_table.dart';

/// Website leads — businesses Google Maps lists with **no website**: the
/// `websiteLeads` collection, filled by the scan. Only businesses confirmed to
/// have none appear; one whose website simply failed to load is not here.
/// Tapping a card opens its Google Maps listing. Paged like every lead list —
/// see [LeadListPage].
class WebsiteLeadsPage extends StatelessWidget {
  const WebsiteLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadListPage(
      config: LeadListConfig(
        collection: LeadCollection.websiteLeads,
        title: 'No Website Leads',
        subtitleEmpty: 'Businesses with no website land here.',
        emptyTitle: 'No website leads yet',
        emptyBody: 'Run a scan — every business Google Maps lists without a website is saved here.',
        emptyIcon: AppIcons.globe,
        tableKind: LeadTableKind.website,
        rowAction: const LeadRowAction(icon: AppIcons.externalLink, tooltip: 'Open in Google Maps'),
        searchHint: 'Search by name, phone, address or category',
        cardExtent: 232,
        headerActions: (context, _) => [
          AppButton.primary(
            label: 'Validate',
            icon: AppIcons.shieldCheck,
            onPressed: () => context.push('/website-leads/validate'),
          ),
        ],
        cardBuilder: (context, lead, {required onTap, required onDelete, required deleting}) =>
            WebsiteLeadCard(lead: lead, onTap: onTap, onDelete: onDelete, deleting: deleting),
        onOpen: (context, lead) async {
          final uri = Uri.tryParse(lead.mapsUrl ?? '');
          final ok = uri != null && uri.hasScheme && await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Google Maps link for this business')));
          }
          return false;
        },
      ),
    );
  }
}
