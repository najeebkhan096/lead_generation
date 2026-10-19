import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/daily_contact_repository.dart';
import '../services/verified_lead_repository.dart';
import '../widgets/verified_lead_card.dart';
import 'verified_leads_page.dart';

/// The Leads tab: the WhatsApp-validated 1-star review leads (see
/// [VerifiedLeadsPage]). The bottom bar (see MainNavigationPage) switches to
/// Sales and More.
class VerifiedLeadsScreen extends StatelessWidget {
  const VerifiedLeadsScreen({
    super.key,
    this.repository,
    this.daily,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  /// For tests (see [VerifiedLeadsPage]).
  final VerifiedLeadRepository? repository;
  final DailyContactRepository? daily;
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;
  final LeadActions actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false, // the bottom bar already keeps clear of the home indicator
      child: VerifiedLeadsPage(
        repository: repository,
        daily: daily,
        collectionQuery: collectionQuery,
        actions: actions,
      ),
    );
  }
}
