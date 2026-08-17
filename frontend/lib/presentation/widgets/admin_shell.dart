import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

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
/// Website Leads earns its own slot despite that bar: it's populated by
/// every scan exactly like Leads is, just filtered on the opposite signal
/// (no website instead of a bad review), so it's just as frequent-use.
///
/// [navigationShell] comes from `app_router.dart`'s `StatefulShellRoute` —
/// each branch (Dashboard/Leads/Website Leads/WhatsApp Tool/Sales/Settings)
/// has its own URL and keeps its own state when you switch away and back,
/// the same way the old `IndexedStack` did, just addressable now.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    (icon: AppIcons.dashboard, label: 'Dashboard'),
    (icon: AppIcons.leads, label: 'Leads'),
    (icon: AppIcons.globe, label: 'Website Leads'),
    (icon: AppIcons.chat, label: 'WhatsApp Tool'),
    (icon: AppIcons.tag, label: 'Sales'),
    (icon: AppIcons.settings, label: 'Settings'),
  ];

  void _openExcelScan(BuildContext context) => context.push('/excel-scan');
  void _openExcelArchive(BuildContext context) => context.push('/excel-archive');

  void _select(int index) => navigationShell.goBranch(
        index,
        // Tapping the already-active tab pops it back to its own root
        // instead of a no-op — matches Material's usual bottom-nav feel.
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  _Sidebar(
                    index: navigationShell.currentIndex,
                    onSelect: _select,
                    onExcelScan: () => _openExcelScan(context),
                    onExcelArchive: () => _openExcelArchive(context),
                  ),
                Expanded(child: navigationShell),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: (i) {
                    if (i == _destinations.length) {
                      _openExcelScan(context);
                    } else if (i == _destinations.length + 1) {
                      _openExcelArchive(context);
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
                    const NavigationDestination(
                      icon: Icon(AppIcons.inbox),
                      label: 'Archive',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.onExcelScan,
    required this.onExcelArchive,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onExcelScan;
  final VoidCallback onExcelArchive;

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
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                child: InkWell(
                  onTap: onExcelArchive,
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(color: AppTheme.neutral200),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.inbox, size: 17, color: AppTheme.subtle),
                        SizedBox(width: 8),
                        Text(
                          'Excel Archive',
                          style: TextStyle(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < AdminShell._destinations.length; i++)
              _SidebarItem(
                icon: AdminShell._destinations[i].icon,
                label: AdminShell._destinations[i].label,
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
