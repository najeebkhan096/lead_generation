import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead_page.dart';
import '../widgets/site_lead_card.dart';
import 'lead_list_page.dart';

/// Email leads — businesses whose website publishes a business email address:
/// the `emailLeads` collection, filled by the scan. Each card shows the
/// address(es) and the page they were found on; tapping opens that page.
/// Paged like every lead list — see [LeadListPage].
class EmailLeadsPage extends StatelessWidget {
  const EmailLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadListPage(
      config: LeadListConfig(
        collection: LeadCollection.emailLeads,
        title: 'Email leads',
        subtitleEmpty: 'Business emails found on websites land here.',
        emptyTitle: 'No email leads yet',
        emptyBody: 'Run a scan — the website of every business it reads is checked for a published business email, '
            'and the ones found are saved here.',
        emptyIcon: AppIcons.mail,
        searchHint: 'Search by name, email, phone or category',
        cardExtent: 324,
        cardBuilder: (context, lead, {required onTap, required onDelete, required deleting}) =>
            EmailLeadCard(lead: lead, onTap: onTap, onDelete: onDelete, deleting: deleting),
        onOpen: (context, lead) async {
          final source = lead.emails.firstOrNull?.sourceUrl ?? lead.emailSourceUrl ?? lead.website;
          final uri = Uri.tryParse(source ?? '');
          final ok = uri != null && uri.hasScheme && await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No source page recorded for this email')));
          }
          return false;
        },
      ),
    );
  }
}
