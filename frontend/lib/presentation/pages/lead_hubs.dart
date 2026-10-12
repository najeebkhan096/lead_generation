import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'email_leads_page.dart';
import 'saved_businesses_page.dart';
import 'website_leads_page.dart';
import 'whatsapp_leads_page.dart';

/// A two-way switch above two full pages. Both pages stay mounted
/// ([IndexedStack]) so scroll position, filters and an in-flight
/// validation survive flipping between them.
class _TwoWayHub extends StatefulWidget {
  const _TwoWayHub({
    required this.initialIndex,
    required this.labels,
    required this.icons,
    required this.pages,
  });

  final int initialIndex;
  final List<String> labels;
  final List<IconData> icons;
  final List<Widget> pages;

  @override
  State<_TwoWayHub> createState() => _TwoWayHubState();
}

class _TwoWayHubState extends State<_TwoWayHub> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: AppTheme.surface,
                selectedBackgroundColor: AppTheme.accent100,
                selectedForegroundColor: AppTheme.accent800,
              ),
              segments: [
                for (var i = 0; i < widget.labels.length; i++)
                  ButtonSegment(value: i, icon: Icon(widget.icons[i], size: 17), label: Text(widget.labels[i])),
              ],
              selected: {_index},
              onSelectionChanged: (s) => setState(() => _index = s.first),
            ),
          ),
        ),
        Expanded(child: IndexedStack(index: _index, children: widget.pages)),
      ],
    );
  }
}

/// **Leads** — the two things a scan finds: businesses with a recent 1-star
/// review, and businesses with no website. Each list carries the same
/// WhatsApp / Email validation bar.
class LeadsHubPage extends StatelessWidget {
  const LeadsHubPage({super.key, this.tab});

  /// `website` opens the no-website list; anything else the review list.
  final String? tab;

  @override
  Widget build(BuildContext context) {
    return _TwoWayHub(
      initialIndex: tab == 'website' ? 1 : 0,
      labels: const ['1-star review leads', 'No-website leads'],
      icons: const [AppIcons.leads, AppIcons.globe],
      pages: const [SavedBusinessesPage(), WebsiteLeadsPage()],
    );
  }
}

/// **Verified** — the output: leads whose WhatsApp number or email address
/// was confirmed, each in its own collection.
class VerifiedHubPage extends StatelessWidget {
  const VerifiedHubPage({super.key, this.tab});

  /// `email` opens the email list; anything else the WhatsApp list.
  final String? tab;

  @override
  Widget build(BuildContext context) {
    return _TwoWayHub(
      initialIndex: tab == 'email' ? 1 : 0,
      labels: const ['WhatsApp', 'Email'],
      icons: const [AppIcons.chat, AppIcons.mail],
      pages: const [WhatsAppLeadsPage(), EmailLeadsPage()],
    );
  }
}
