import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

const _wideBreakpoint = 900.0;

/// One navigation item of the admin console.
typedef _Destination = ({IconData icon, String label, String hint});

/// The console's persistent frame: a sidebar (bottom bar on narrow
/// windows) that follows the work in the order it happens —
///
///   Scan → Archive → Leads → Verified
///
/// — plus Dashboard (overview) first and More (connections,
/// sales, watchlist, users) last. Everything beyond the core flow lives
/// behind More instead of competing for a slot here.
///
/// [navigationShell] comes from `app_router.dart`'s `StatefulShellRoute`;
/// branches past [moreIndex] (Sales, WhatsApp tool) are opened
/// from More and light up More while they're open.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = <_Destination>[
    (icon: AppIcons.dashboard, label: 'Dashboard', hint: 'Overview'),
    (icon: AppIcons.search, label: 'Scan', hint: 'Find leads'),
    (icon: AppIcons.inbox, label: 'Archive', hint: 'Finished scans'),
    (icon: AppIcons.leads, label: 'Leads', hint: '1-star reviews'),
    (icon: AppIcons.shieldCheck, label: 'Verified', hint: 'WhatsApp'),
    (icon: AppIcons.settings, label: 'More', hint: 'Tools & access'),
  ];

  /// Index of "More" — also the nav item shown selected for every shell
  /// branch after it.
  static const moreIndex = 5;

  int get _selected =>
      navigationShell.currentIndex > moreIndex ? moreIndex : navigationShell.currentIndex;

  void _select(int index) => navigationShell.goBranch(
        index,
        // Tapping the already-active item pops it back to its own root
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
                if (wide) _Sidebar(index: _selected, onSelect: _select),
                Expanded(child: navigationShell),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selected,
                  onDestinationSelected: _select,
                  backgroundColor: AppTheme.surface,
                  indicatorColor: AppTheme.accent100,
                  destinations: [
                    for (final d in _destinations)
                      NavigationDestination(icon: Icon(d.icon), label: d.label),
                  ],
                ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
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
                    decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
                    child: const Icon(AppIcons.target, size: 18, color: AppTheme.accent700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LeadFinder',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16),
                        ),
                        const Text(
                          'Admin console',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.faint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            for (var i = 0; i < AdminShell._destinations.length; i++)
              _SidebarItem(
                destination: AdminShell._destinations[i],
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
  const _SidebarItem({required this.destination, required this.selected, required this.onTap});

  final _Destination destination;
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
                Icon(destination.icon, size: 19, color: selected ? AppTheme.accent700 : AppTheme.subtle),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          color: selected ? AppTheme.accent800 : AppTheme.ink,
                        ),
                      ),
                      Text(
                        destination.hint,
                        style: const TextStyle(fontSize: 11, color: AppTheme.faint),
                      ),
                    ],
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
