import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import 'app_sidebar.dart';
import 'nav_model.dart';

/// The console's persistent frame for the pages that keep their state when you
/// switch away: the [StatefulShellRoute] branches in `app_router.dart`.
///
/// Wide windows get the sidebar beside the content (collapsible to an icon
/// rail); narrow ones get a top bar and the same sidebar as a drawer.
///
/// Branches without a nav item of their own (Sales, WhatsApp tool, the extra
/// lead lists) still light up the right item — see `nav_model.dart`.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// The shell branch of "More".
  static const moreBranch = 5;

  /// The shell branch of Jobs Finder — appended after the older branches so
  /// none of their indexes moved.
  static const jobsBranch = 10;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    return AppFrame(
      location: location,
      onNavigate: (item) {
        final branch = item.branch;
        if (branch != null && item.query.isEmpty) {
          // Tapping the already-open item pops it back to its own root.
          navigationShell.goBranch(branch, initialLocation: branch == navigationShell.currentIndex);
        } else {
          context.go(item.target);
        }
      },
      child: navigationShell,
    );
  }
}

/// The same frame around routes that are not shell branches (details pages,
/// Watchlist, Users, …), so the sidebar never disappears.
class PlainShell extends StatelessWidget {
  const PlainShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppFrame(location: location, onNavigate: (item) => context.go(item.target), child: child);
  }
}

/// Sidebar + content, responsive.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.location, required this.onNavigate, required this.child});

  final String location;
  final ValueChanged<NavItem> onNavigate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selected = navItemFor(location);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < AppBreakpoints.mobile) {
          return _MobileFrame(selected: selected, onNavigate: onNavigate, child: child);
        }
        return ValueListenableBuilder<bool?>(
          valueListenable: SidebarPrefs.collapsed,
          builder: (context, preference, _) {
            final collapsed = preference ?? width < AppBreakpoints.compact;
            return Scaffold(
              backgroundColor: AppTheme.background,
              body: Row(
                children: [
                  AppSidebar(
                    selected: selected,
                    onSelect: onNavigate,
                    collapsed: collapsed,
                    onToggleCollapsed: () => SidebarPrefs.set(!collapsed),
                  ),
                  Expanded(child: ClipRect(child: child)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MobileFrame extends StatelessWidget {
  const _MobileFrame({required this.selected, required this.onNavigate, required this.child});

  final NavItem? selected;
  final ValueChanged<NavItem> onNavigate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(AppIcons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(selected?.label ?? 'LeadFinder', style: Theme.of(context).textTheme.titleMedium),
      ),
      drawer: Drawer(
        width: sidebarExpandedWidth,
        backgroundColor: AppTheme.sidebar,
        shape: const RoundedRectangleBorder(),
        child: Builder(
          builder: (drawerContext) => AppSidebar(
            selected: selected,
            collapsed: false,
            inDrawer: true,
            onSelect: (item) {
              Navigator.of(drawerContext).pop();
              onNavigate(item);
            },
          ),
        ),
      ),
      body: child,
    );
  }
}
