import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead_page.dart';
import '../widgets/saved_business_card.dart';
import 'lead_list_page.dart';

/// Every business whose phone number a real WhatsApp check confirmed — the
/// `whatsappLeads` collection. Validating a review lead or a no-website lead
/// copies it here; this is the list to work from. Tapping a card opens the
/// chat. Paged like every lead list — see [LeadListPage].
class WhatsAppLeadsPage extends StatelessWidget {
  const WhatsAppLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadListPage(
      config: LeadListConfig(
        collection: LeadCollection.whatsappLeads,
        title: 'WhatsApp leads',
        subtitleEmpty: 'Businesses with a confirmed WhatsApp number will land here.',
        emptyTitle: 'No WhatsApp leads yet',
        emptyBody: 'Open Leads (or an Excel Archive) and tap WhatsApp to check numbers — '
            'the ones that are on WhatsApp are saved here.',
        emptyIcon: AppIcons.chat,
        searchHint: 'Search by name, phone or address',
        sourceFilter: true,
        cardBuilder: (context, lead, {required onTap, required onDelete, required deleting}) =>
            SavedBusinessCard(lead: lead, onTap: onTap, onDelete: onDelete, deleting: deleting),
        onOpen: (context, lead) async {
          final url = (lead.waLink?.isNotEmpty ?? false)
              ? lead.waLink!
              : 'https://wa.me/${(lead.phone ?? '').replaceAll(RegExp(r'\D'), '')}';
          final uri = Uri.tryParse(url);
          final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
          }
          return false;
        },
      ),
    );
  }
}
