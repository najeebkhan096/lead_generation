import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead_page.dart';
import '../widgets/email_lead_card.dart';
import 'lead_list_page.dart';

/// Every business the email validator found and verified a contact email
/// for — the `emailLeads` collection. Populated from a validation run on
/// Leads or an Excel Archive. Paged like every lead list — see
/// [LeadListPage].
class EmailLeadsPage extends StatelessWidget {
  const EmailLeadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadListPage(
      config: LeadListConfig(
        collection: LeadCollection.emailLeads,
        title: 'Email leads',
        subtitleEmpty: 'Businesses with a verified contact email will land here.',
        emptyTitle: 'No email leads yet',
        emptyBody: 'Open Leads (or an Excel Archive) and tap Email — each business is checked '
            'for a contact address, and the verified ones are saved here.',
        emptyIcon: AppIcons.mail,
        searchHint: 'Search by name, email or website',
        cardExtent: 262,
        cardBuilder: (context, lead, {required onTap, required onDelete, required deleting}) =>
            EmailLeadCard(lead: lead, onTap: onTap, onDelete: onDelete, deleting: deleting),
        onOpen: (context, lead) => context.push<bool>('/email-leads/details', extra: lead),
        headerActions: (context, state) {
          // Only what's loaded — a page at a time — so say so.
          final emails = <String>{
            for (final l in state.leads)
              if (l.email != null && l.email!.isNotEmpty) l.email!,
          };
          if (emails.isEmpty) return const [];
          return [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                onPressed: () => copyToClipboard(
                  context,
                  emails.join('\n'),
                  'Copied ${emails.length} email${emails.length == 1 ? '' : 's'}',
                ),
                icon: const Icon(AppIcons.copy, size: 16),
                label: Text('Copy ${emails.length} email${emails.length == 1 ? '' : 's'}'),
              ),
            ),
          ];
        },
      ),
    );
  }
}
