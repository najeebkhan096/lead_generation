import 'package:go_router/go_router.dart';

import '../../domain/entities/lead.dart';
import '../../presentation/pages/business_details_page.dart';
import '../../presentation/pages/dashboard_page.dart';
import '../../presentation/pages/excel_archive_page.dart';
import '../../presentation/pages/excel_scan_page.dart';
import '../../presentation/pages/multi_scan_page.dart';
import '../../presentation/pages/sales_page.dart';
import '../../presentation/pages/saved_businesses_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/state_scan_page.dart';
import '../../presentation/pages/watchlist_page.dart';
import '../../presentation/pages/website_leads_page.dart';
import '../../presentation/pages/whatsapp_checker_page.dart';
import '../../presentation/pages/whatsapp_validated_archive_page.dart';
import '../../presentation/widgets/admin_shell.dart';

/// Every top-level section gets its own URL (`/leads`, `/settings`, …)
/// instead of the whole app living behind one address — back/forward,
/// refresh, and bookmarking all work per-page now.
///
/// The five primary sections (Dashboard/Leads/WhatsApp Tool/Sales/
/// Settings) are [StatefulShellRoute] branches — [AdminShell] wraps them
/// with the persistent sidebar/bottom-nav, and each branch keeps its own
/// state (scroll position, in-flight loads) when you switch away and back,
/// exactly like the `IndexedStack` this replaced. Everything reached one
/// level down (Excel Scan, Scan Progress, Excel Archive, Watchlist,
/// WhatsApp Verified) still gets a real URL, just outside the shell so it
/// opens full-screen with its own back button.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AdminShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/leads', builder: (context, state) => const SavedBusinessesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/website-leads', builder: (context, state) => const WebsiteLeadsPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/whatsapp', builder: (context, state) => const WhatsAppCheckerPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/sales', builder: (context, state) => const SalesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
        ]),
      ],
    ),
    GoRoute(path: '/excel-scan', builder: (context, state) => const ExcelScanPage()),
    GoRoute(path: '/scan-progress', builder: (context, state) => const StateScanPage()),
    GoRoute(path: '/excel-archive', builder: (context, state) => const ExcelArchivePage()),
    GoRoute(path: '/watchlist', builder: (context, state) => const WatchlistPage()),
    GoRoute(path: '/whatsapp-verified', builder: (context, state) => const WhatsAppValidatedArchivePage()),
    // Legacy/dormant multi-country scan dashboard — still reachable from
    // the handful of old archives that predate the state/city scan engine.
    GoRoute(path: '/multi-scan', builder: (context, state) => const MultiScanPage()),
    // Carries its [Lead] via `extra` rather than fetching by id — an
    // internal admin tool's detail drill-down, not something meant to be
    // cold-loaded from a bare URL. Falls back to the Leads list if opened
    // without it (e.g. a stale/shared link).
    GoRoute(
      path: '/leads/details',
      builder: (context, state) {
        final lead = state.extra as Lead?;
        if (lead == null) return const SavedBusinessesPage();
        return BusinessDetailsPage(lead: lead);
      },
    ),
  ],
);
