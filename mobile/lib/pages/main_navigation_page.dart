import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'deals_page.dart';
import 'profile_page.dart';
import 'sales_page.dart';
import 'verified_leads_screen.dart';

/// The salesman's app, in three tabs:
///
///   Leads  — the WhatsApp-validated 1-star review leads, New and Contacted
///            (see [VerifiedLeadsScreen]); the daily limit is shown here.
///   Deals  — the contacted leads this salesman has marked a deal done.
///   Sales  — the salesman's own orders and earnings.
///   More   — the account, settings and Sign out.
///
/// Every tab stays built (IndexedStack), so each keeps its scroll position and
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
          VerifiedLeadsScreen(),
          DealsPage(),
          SalesPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(AppIcons.chat), label: 'Leads'),
          NavigationDestination(icon: Icon(AppIcons.handshake), label: 'Deals'),
          NavigationDestination(icon: Icon(AppIcons.wallet), label: 'Sales'),
          NavigationDestination(icon: Icon(AppIcons.user), label: 'More'),
        ],
      ),
    );
  }
}
