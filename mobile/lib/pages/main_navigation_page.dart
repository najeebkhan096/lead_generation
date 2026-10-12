import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'leads_page.dart';
import 'profile_page.dart';
import 'verified_leads_page.dart';

/// The app follows the same flow as the web console:
///
///   Leads  →  WhatsApp / Email (the verified output)  →  More
///
/// Leads are what a scan found (1-star review and no-website leads); the
/// WhatsApp and Email tabs are the leads each validator confirmed, each from
/// its own collection. Outreach chat, sales, archives and the account live
/// under More so the main bar stays four items.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    LeadsPage(),
    VerifiedLeadsPage(kind: VerifiedKind.whatsapp),
    VerifiedLeadsPage(kind: VerifiedKind.email),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(AppIcons.compass), label: 'Leads'),
          NavigationDestination(icon: Icon(AppIcons.chat), label: 'WhatsApp'),
          NavigationDestination(icon: Icon(AppIcons.mail), label: 'Email'),
          NavigationDestination(icon: Icon(AppIcons.more), label: 'More'),
        ],
      ),
    );
  }
}
