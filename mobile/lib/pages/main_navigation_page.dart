import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'leads_page.dart';
import 'whatsapp_verified_leads_page.dart';
import 'sales_page.dart';
import 'profile_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    WhatsAppVerifiedLeadsPage(),
    LeadsPage(),
    SalesPage(),
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
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(AppIcons.chat),
            label: 'WA',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.compass),
            label: 'Leads',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.wallet),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.user),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
