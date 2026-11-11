import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/verified_lead_card.dart';
import 'website_leads_page.dart';

/// The No Website tab: the WhatsApp-validated no-website leads (see
/// [WebsiteLeadsPage]), kept clear of the status bar. The bottom bar (see
/// MainNavigationPage) switches to the other tabs.
class WebsiteLeadsScreen extends StatelessWidget {
  const WebsiteLeadsScreen({
    super.key,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  /// For tests (see [WebsiteLeadsPage]).
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;
  final LeadActions actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, // the bottom bar already keeps clear of the home indicator
      child: WebsiteLeadsPage(collectionQuery: collectionQuery, actions: actions),
    );
  }
}
