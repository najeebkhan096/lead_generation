import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'profile_page.dart';
import 'website_leads_screen.dart';

/// The salesman's app, in two tabs:
///
///   No Website — the WhatsApp-validated leads for businesses with no website
///            (see [WebsiteLeadsScreen]); the first tab. The daily limit is
///            shown here.
///   Profile — the account, and everything else: the 1-star review Leads, Deals
///            and Sales, the archive, settings and Sign out (see [ProfilePage]).
///
/// Both tabs stay built (IndexedStack), so each keeps its scroll position and
/// loaded pages when you switch.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          WebsiteLeadsScreen(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(AppIcons.globe), label: 'No Website'),
          NavigationDestination(icon: Icon(AppIcons.user), label: 'Profile'),
        ],
      ),
    );
  }
}
