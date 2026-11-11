import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/lead_page.dart';
import '../design_system/design_system.dart';
import '../widgets/saved_business_card.dart';
import 'lead_list_page.dart';
import '../widgets/lead_table.dart';

/// Every business whose phone number a real WhatsApp check confirmed, in two
/// tabs — the two kinds of scan are different things and are kept apart:
///
///  * **No website** — the leads a no-website scan found, confirmed on WhatsApp
///    (`websiteLeads` with `hasWhatsApp`).
///  * **1-star reviews** — the 1-star review leads confirmed on WhatsApp
///    (`whatsappLeads`, review kind).
///
/// Each tab is a full lead list with its own categories (only the searches
/// that kind of scan ran), search and paging — see [LeadListPage]. Tapping a
/// card opens the chat.
class WhatsAppLeadsPage extends StatelessWidget {
  const WhatsAppLeadsPage({super.key, this.initialTab = 0});

  /// 0 = No website, 1 = 1-star reviews.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.pageGutter(MediaQuery.sizeOf(context).width);
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, 0),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(icon: Icon(AppIcons.globe, size: 18), text: 'No website'),
                  Tab(icon: Icon(AppIcons.thumbsDown, size: 18), text: '1-star reviews'),
                ],
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _VerifiedList(
                  collection: LeadCollection.websiteVerified,
                  title: 'WhatsApp Verified · No website',
                  subtitleEmpty: 'No-website leads with a confirmed WhatsApp number will land here.',
                  emptyTitle: 'No verified no-website leads yet',
                  emptyBody: 'Validate WhatsApp for a no-website search (No Website → Validate) — '
                      'the numbers that are on WhatsApp are listed here.',
                ),
                _VerifiedList(
                  collection: LeadCollection.whatsappReviewLeads,
                  title: 'WhatsApp Verified · 1-star reviews',
                  subtitleEmpty: '1-star leads with a confirmed WhatsApp number will land here.',
                  emptyTitle: 'No verified 1-star leads yet',
                  emptyBody: 'Open an Excel Archive and validate WhatsApp — '
                      'the numbers that are on WhatsApp are saved here.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab: a verified-leads list of [collection].
class _VerifiedList extends StatefulWidget {
  const _VerifiedList({
    required this.collection,
    required this.title,
    required this.subtitleEmpty,
    required this.emptyTitle,
    required this.emptyBody,
  });

  final LeadCollection collection;
  final String title;
  final String subtitleEmpty;
  final String emptyTitle;
  final String emptyBody;

  @override
  State<_VerifiedList> createState() => _VerifiedListState();
}

class _VerifiedListState extends State<_VerifiedList> with AutomaticKeepAliveClientMixin {
  // Both tabs stay built, so each keeps its scroll position, search and category.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LeadListPage(
      config: LeadListConfig(
        collection: widget.collection,
        title: widget.title,
        subtitleEmpty: widget.subtitleEmpty,
        emptyTitle: widget.emptyTitle,
        emptyBody: widget.emptyBody,
        emptyIcon: AppIcons.chat,
        tableKind: LeadTableKind.whatsapp,
        rowAction: const LeadRowAction(icon: AppIcons.chat, tooltip: 'Open WhatsApp'),
        searchHint: 'Search by name, phone or address',
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
