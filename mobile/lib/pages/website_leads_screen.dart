import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/daily_contact_repository.dart';
import '../services/verified_lead_repository.dart';
import '../widgets/verified_lead_card.dart';
import 'verified_leads_page.dart';

/// The No Website tab: the WhatsApp-validated no-website leads, New and
/// Contacted (see [VerifiedLeadsPage] with [LeadKind.noWebsite]), kept clear of
/// the status bar. Contacting one counts against the salesman's daily limit,
/// the same limit as the 1-star leads. The bottom bar (see MainNavigationPage)
/// switches to Profile.
class WebsiteLeadsScreen extends StatelessWidget {
  const WebsiteLeadsScreen({
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
        kind: LeadKind.noWebsite,
        repository: repository,
        daily: daily,
        collectionQuery: collectionQuery,
        actions: actions,
      ),
    );
  }
}
