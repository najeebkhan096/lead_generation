import 'package:flutter/material.dart';

import 'saved_businesses_page.dart';
import 'whatsapp_leads_page.dart';

/// A two-way switch above two full pages. Both pages stay mounted
/// ([IndexedStack]) so scroll position, filters and an in-flight
/// validation survive flipping between them.
/// **Leads** — businesses with a recent 1-star review, verified on WhatsApp.
class LeadsHubPage extends StatelessWidget {
  const LeadsHubPage({super.key, this.tab});

  /// Kept for old links (`?tab=`); there is one list now.
  final String? tab;

  @override
  Widget build(BuildContext context) => const SavedBusinessesPage();
}

/// **Verified** — the output: 1-star review leads whose WhatsApp number was confirmed.
class VerifiedHubPage extends StatelessWidget {
  const VerifiedHubPage({super.key, this.tab});

  /// Kept for old links (`?tab=`); there is one list now.
  final String? tab;

  @override
  Widget build(BuildContext context) => const WhatsAppLeadsPage();
}
