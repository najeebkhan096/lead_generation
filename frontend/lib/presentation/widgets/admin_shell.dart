import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../pages/dashboard_page.dart';
import '../pages/excel_scan_page.dart';
import '../pages/sales_page.dart';
import '../pages/saved_businesses_page.dart';
import '../pages/settings_page.dart';
import '../pages/whatsapp_checker_page.dart';

const _wideBreakpoint = 900.0;

/// The admin console's persistent frame: a sidebar (or bottom bar on
/// narrow windows) around the frequent-use sections, with Excel Scan as
/// the one permanent entry point for starting a scan (the classic
/// single-search flow was retired — Excel Scan covers every case now).
///
/// Kept deliberately short — everything reached less than daily (Watchlist,
/// Excel Archive, WhatsApp Verified) lives one level down in Settings
/// instead of competing for a slot here. "WhatsApp Business" was folded
/// into Leads' existing verified-only filter switch rather than kept as a
/// separate destination, and Sales Dashboard/Sales merged into one page
/// with an Overview/Manage tab switch — same data, fewer places to look.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _pages = [
    DashboardPage(),
    SavedBusinessesPage(),
    WhatsAppCheckerPage(),
    SalesPage(),
    SettingsPage(),
  ];

  static const _destinations = [
    (icon: AppIcons.dashboard, label: 'Dashboard'),
    (icon: AppIcons.leads, label: 'Leads'),
    (icon: AppIcons.chat, label: 'WhatsApp Tool'),
    (icon: AppIcons.tag, label: 'Sales'),
    (icon: AppIcons.settings, label: 'Settings'),
  ];

  void _openExcelScan() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ExcelScanPage()),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        // The IndexedStack carries each tab's live state (fetched leads,
        // search text, scroll position). It keeps one stable key here so
        // Flutter's keyed-list reconciliation preserves that state across
        // the wide/narrow toggle instead of tearing the whole subtree
        // down just because the sidebar appears or disappears next to it.
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  _Sidebar(
                    index: _index,
                    onSelect: _select,
                    onExcelScan: _openExcelScan,
                  ),
                Expanded(
                  child: IndexedStack(
                    key: const ValueKey('shell-content'),
                    index: _index,
                    children: _pages,
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) {
                    if (i == _destinations.length) {
                      _openExcelScan();
                    } else {
                      _select(i);
                    }
                  },
                  backgroundColor: AppTheme.surface,
                  indicatorColor: AppTheme.accent100,
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        label: d.label,
                      ),
                    const NavigationDestination(
                      icon: Icon(AppIcons.download),
                      label: 'Excel Scan',
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _select(int index) => setState(() => _index = index);
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.onExcelScan,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onExcelScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.neutral200)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(AppIcons.target,
                        size: 18, color: AppTheme.accent700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LeadFinder',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 16),
                        ),
                        const Text(
                          'Admin console',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: AppTheme.accent500,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                child: InkWell(
                  onTap: onExcelScan,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.download, size: 18, color: AppTheme.surface),
                        SizedBox(width: 8),
                        Text(
                          'Excel Scan',
                          style: TextStyle(
                            color: AppTheme.surface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < _AdminShellState._destinations.length; i++)
              _SidebarItem(
                icon: _AdminShellState._destinations[i].icon,
                label: _AdminShellState._destinations[i].label,
                selected: i == index,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppTheme.accent100 : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 19,
                    color: selected ? AppTheme.accent700 : AppTheme.subtle),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppTheme.accent800 : AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
