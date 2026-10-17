import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/verified_lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/verified_lead_card.dart';
import 'profile_page.dart';
import 'verified_leads_page.dart';

/// Opens "More" — sales, settings, Sign out — as its own screen with a back
/// arrow (the page draws its own "More" header).
void openMore(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(), body: const ProfilePage())),
  );
}

/// The phone's one screen: the WhatsApp-validated 1-star review leads (see
/// [VerifiedLeadsPage]), with the account button at the top right.
class VerifiedLeadsScreen extends StatelessWidget {
  const VerifiedLeadsScreen({
    super.key,
    this.repository,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  /// For tests (see [VerifiedLeadsPage]).
  final VerifiedLeadRepository? repository;
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;
  final LeadActions actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: IconButton(
                tooltip: 'More',
                onPressed: () => openMore(context),
                icon: const Icon(AppIcons.user),
                color: t.subtle,
              ),
            ),
          ),
          Expanded(
            child: VerifiedLeadsPage(
              repository: repository,
              collectionQuery: collectionQuery,
              actions: actions,
            ),
          ),
        ],
      ),
    );
  }
}
