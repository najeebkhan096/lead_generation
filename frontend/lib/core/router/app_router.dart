import 'package:go_router/go_router.dart';

import '../../domain/entities/lead.dart';
import '../../presentation/pages/business_details_page.dart';
import '../../presentation/pages/dashboard_page.dart';
import '../../presentation/pages/email_lead_details_page.dart';
import '../../presentation/pages/email_verified_archive_page.dart';
import '../../presentation/pages/email_leads_page.dart';
import '../../presentation/pages/excel_archive_page.dart';
import '../../presentation/pages/excel_scan_page.dart';
import '../../presentation/pages/multi_scan_page.dart';
import '../../presentation/pages/sales_page.dart';
import '../../presentation/pages/outreach_page.dart';
import '../../presentation/pages/lead_hubs.dart';
import '../../presentation/pages/saved_businesses_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/users_page.dart';
import '../../presentation/pages/state_scan_page.dart';
import '../../presentation/pages/watchlist_page.dart';
import '../../presentation/pages/whatsapp_checker_page.dart';
import '../../presentation/pages/whatsapp_validated_archive_page.dart';
import '../../presentation/widgets/admin_shell.dart';

/// The app is organized around one flow: **Scan → Archive → Leads →
/// Verified**, with everything else behind **More**.
///
///  * `/scan`     start a scan (and `/scan-progress` to watch it)
///  * `/archive`  finished scans as Excel workbooks — validate from here
///  * `/leads`    saved leads: 1-star review leads | no-website leads
///  * `/verified` the output: WhatsApp-verified | email-verified leads
///  * `/more`     WhatsApp connection, outreach, sales, watchlist, users
///
/// These are [StatefulShellRoute] branches — [AdminShell] wraps them with
/// the persistent sidebar/bottom-nav and each branch keeps its own state
/// when you switch away and back. Branches 6+ (Sales, Outreach, WhatsApp
/// tool) are reached from More: they live in the shell so they keep the
/// navigation, but have no nav item of their own.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    // Old URLs from before the navigation was simplified.
    switch (state.uri.path) {
      case '/excel-scan':
        return '/scan';
      case '/excel-archive':
        return '/archive';
      case '/website-leads':
        return '/leads?tab=website';
      case '/email-leads':
        return '/verified?tab=email';
      case '/whatsapp-verified-leads':
        return '/verified';
      case '/settings':
        return '/more';
    }
    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AdminShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/scan', builder: (context, state) => const ExcelScanPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/archive', builder: (context, state) => const ExcelArchivePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/leads',
            builder: (context, state) => LeadsHubPage(tab: state.uri.queryParameters['tab']),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/verified',
            builder: (context, state) => VerifiedHubPage(tab: state.uri.queryParameters['tab']),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/more', builder: (context, state) => const SettingsPage()),
        ]),
        // Reached from More — in the shell, but not in the nav.
        StatefulShellBranch(routes: [
          GoRoute(path: '/sales', builder: (context, state) => const SalesPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/outreach', builder: (context, state) => const OutreachPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/whatsapp', builder: (context, state) => const WhatsAppCheckerPage()),
        ]),
      ],
    ),
    GoRoute(path: '/scan-progress', builder: (context, state) => const StateScanPage()),
    GoRoute(path: '/watchlist', builder: (context, state) => const WatchlistPage()),
    GoRoute(path: '/users', builder: (context, state) => const UsersPage()),
    GoRoute(path: '/whatsapp-verified', builder: (context, state) => const WhatsAppValidatedArchivePage()),
    GoRoute(path: '/email-verified', builder: (context, state) => const EmailVerifiedArchivePage()),
    // Legacy/dormant multi-country scan dashboard — still reachable from
    // the handful of old archives that predate the state/city scan engine.
    GoRoute(path: '/multi-scan', builder: (context, state) => const MultiScanPage()),
    // Same `extra` convention as `/leads/details` — falls back to the Email
    // Leads list when opened without a lead (e.g. a refreshed tab).
    GoRoute(
      path: '/email-leads/details',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is Lead) return EmailLeadDetailsPage(lead: extra);
        return const EmailLeadsPage();
      },
    ),
    // Carries its [Lead] via `extra` rather than fetching by id — an
    // internal admin tool's detail drill-down, not something meant to be
    // cold-loaded from a bare URL. Falls back to the Leads list if opened
    // without it (e.g. a stale/shared link).
    GoRoute(
      path: '/leads/details',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is LeadDetailsArgs) {
          return BusinessDetailsPage(lead: extra.lead, isWebsiteLead: extra.isWebsiteLead);
        }
        if (extra is Lead) return BusinessDetailsPage(lead: extra);
        return const SavedBusinessesPage();
      },
    ),
  ],
);
