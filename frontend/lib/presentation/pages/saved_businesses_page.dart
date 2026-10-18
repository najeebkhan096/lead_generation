import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead_page.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart' show LeadDetailsArgs;
import 'lead_list_page.dart';

/// Review leads — businesses with a recent 1-star review. A paged list: see
/// [LeadListPage]. The WhatsApp validation bar validates the leads
/// that are loaded; the category filter and search narrow them on the
/// server.
class SavedBusinessesPage extends StatelessWidget {
  const SavedBusinessesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LeadListPage(
      config: LeadListConfig(
        collection: LeadCollection.reviewLeads,
        title: 'Review leads',
        subtitleEmpty: 'Businesses with a recent 1-star review land here.',
        emptyTitle: 'No review leads yet',
        emptyBody: 'Run a scan — every business with a recent 1-star review is saved here.',
        emptyIcon: AppIcons.leads,
        searchHint: 'Search by name, phone, address or category',
        validationCollection: 'leads',
        verifiedFilter: true,
        cardBuilder: (context, lead, {required onTap, required onDelete, required deleting}) =>
            SavedBusinessCard(lead: lead, onTap: onTap, onDelete: onDelete, deleting: deleting),
        onOpen: (context, lead) => context.push<bool>('/leads/details', extra: LeadDetailsArgs(lead: lead)),
      ),
    );
  }
}
