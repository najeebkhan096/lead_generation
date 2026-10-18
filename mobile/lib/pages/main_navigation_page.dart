import 'package:flutter/material.dart';

import 'verified_leads_screen.dart';

/// The app is the WhatsApp-validated 1-star review leads, in two lists —
/// **New** and **Contacted** (see [VerifiedLeadsScreen]). The account button
/// at the top right opens "More": sales, settings and Sign out.
/// Unvalidated leads (scans) are not shown on the phone; validate them in the
/// web console and they appear here on their own.
class MainNavigationPage extends StatelessWidget {
  const MainNavigationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: VerifiedLeadsScreen());
  }
}
