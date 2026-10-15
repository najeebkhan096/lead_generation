import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/verified_lead_repository.dart';
import '../theme/app_theme.dart';
import '../utils/outreach_email.dart';
import '../widgets/segmented_tab_bar.dart';
import '../widgets/verified_lead_card.dart';
import 'profile_page.dart';
import 'verified_leads_page.dart';

/// Opens "More" — outreach chat, sales, settings, Sign out — as its own
/// screen with a back arrow (the page draws its own "More" header).
void openMore(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(), body: const ProfilePage())),
  );
}

/// One bottom-bar destination: the leads found by one signal — **1-star
/// review** or **no website** — split into its two verified channels,
/// **WhatsApp** and **Email**.
class SignalScreen extends StatelessWidget {
  const SignalScreen({
    super.key,
    required this.signal,
    this.repository,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  final LeadSignal signal;

  /// For tests (see [VerifiedLeadsPage]).
  final VerifiedLeadRepository? repository;
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;
  final LeadActions actions;

  Widget _page(VerifiedKind kind) => _KeepAlive(
        child: VerifiedLeadsPage(
          kind: kind,
          signal: signal,
          repository: repository,
          collectionQuery: collectionQuery,
          actions: actions,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Expanded(child: SegmentedTabBar(labels: ['WhatsApp', 'Email'])),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'More',
                    onPressed: () => openMore(context),
                    icon: const Icon(AppIcons.user),
                    color: t.subtle,
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [_page(VerifiedKind.whatsapp), _page(VerifiedKind.email)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a tab's list (scroll position, loaded pages) when you switch tabs.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
