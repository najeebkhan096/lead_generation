import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'saved_businesses_page.dart';
import 'whatsapp_leads_page.dart';
import 'favorites_page.dart';
import 'deals_page.dart';
import 'profile_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = [
    SavedBusinessesPage(),
    WhatsAppLeadsPage(),
    FavoritesPage(),
    DealsPage(),
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
            icon: Icon(AppIcons.compass),
            label: 'Leads',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.chat),
            label: 'WhatsApp',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.heart),
            label: 'Favorites',
          ),
          NavigationDestination(
            icon: Icon(AppIcons.handshake),
            label: 'Deals',
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
