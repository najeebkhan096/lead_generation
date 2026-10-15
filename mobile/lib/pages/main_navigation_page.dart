import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/outreach_email.dart';
import 'signal_screen.dart';

/// The app is the verified leads, in two groups that mirror how they were
/// found — one bottom-bar destination each:
///
///   1-star reviews  |  No website
///
/// and inside each, two lists: **WhatsApp** and **Email** (see
/// [SignalScreen]), each with New and Contacted. The account button at the
/// top right opens "More": outreach chat, sales, settings and Sign out.
/// Unvalidated leads (scans) are not shown on the phone; validate them in the
/// web console and they appear here on their own.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    SignalScreen(signal: LeadSignal.review),
    SignalScreen(signal: LeadSignal.noWebsite),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Both stay built, so each keeps its tab, scroll and loaded pages.
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(AppIcons.star), label: '1-star reviews'),
          NavigationDestination(icon: Icon(AppIcons.globe), label: 'No website'),
        ],
      ),
    );
  }
}
