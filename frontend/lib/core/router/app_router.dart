import 'package:go_router/go_router.dart';

import '../../domain/entities/lead.dart';
import '../../domain/entities/twilio_test_lead.dart';
import '../../presentation/pages/business_details_page.dart';
import '../../presentation/pages/dashboard_page.dart';
import '../../presentation/pages/email_leads_page.dart';
import '../../presentation/pages/website_leads_page.dart';
import '../../presentation/pages/excel_archive_page.dart';
import '../../presentation/pages/jobs/job_details_page.dart';
import '../../presentation/pages/jobs/jobs_hub_page.dart';
import '../../presentation/pages/excel_scan_page.dart';
import '../../presentation/pages/multi_scan_page.dart';
import '../../presentation/pages/no_website_validation_page.dart';
import '../../presentation/pages/clients_page.dart';
import '../../presentation/pages/sales_page.dart';
import '../../presentation/pages/lead_hubs.dart';
import '../../presentation/pages/saved_businesses_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../../presentation/pages/app_update_page.dart';
import '../../presentation/pages/salesman_contacted_leads_page.dart';
import '../../presentation/pages/salesman_stats_page.dart';
import '../../presentation/pages/users_page.dart';
import '../../presentation/pages/state_scan_page.dart';
import '../../presentation/pages/twilio_test_chat_page.dart';
import '../../presentation/pages/twilio_test_leads_page.dart';
import '../../presentation/pages/watchlist_page.dart';
import '../../presentation/pages/whatsapp_checker_page.dart';
import '../../presentation/pages/whatsapp_validated_archive_page.dart';
import '../../presentation/widgets/admin_shell.dart';

/// The app is organized around one flow: **Scan → Archive → Leads →
/// Verified**, with everything else behind **More**.
///
///  * `/scan`     start a scan (and `/scan-progress` to watch it)
///  * `/archive`  finished scans as Excel workbooks — validate from here
///  * `/leads`    saved leads: 1-star review leads
///  * `/verified` the output: WhatsApp-verified leads
///  * `/more`     WhatsApp connection, sales, watchlist, users
///  * `/jobs`     Jobs Finder: its own section (overview, search, scans, jobs,
///                tracker, sources), independent of the lead flow above;
///                `/jobs/:id` is one job in full
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
      case '/whatsapp-verified-leads':
        return '/verified';
      case '/settings':
        return '/more';
    }
    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AdminShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scan',
              builder: (context, state) => ExcelScanPage(type: state.uri.queryParameters['type']),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/archive',
              builder: (context, state) => const ExcelArchivePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/leads',
              builder: (context, state) =>
                  LeadsHubPage(tab: state.uri.queryParameters['tab']),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/verified',
              builder: (context, state) =>
                  VerifiedHubPage(tab: state.uri.queryParameters['tab']),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
        // Reached from More — in the shell, but not in the nav.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/sales',
              builder: (context, state) => const SalesPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/whatsapp',
              builder: (context, state) => const WhatsAppCheckerPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/website-leads',
              builder: (context, state) => const WebsiteLeadsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/email-leads',
              builder: (context, state) => const EmailLeadsPage(),
            ),
          ],
        ),
        // Jobs Finder — in the nav (see AdminShell.jobsBranch).
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/jobs',
              builder: (context, state) =>
                  JobsHubPage(tab: state.uri.queryParameters['tab']),
            ),
          ],
        ),
      ],
    ),
    // Everything else is a plain route, but still inside the frame so the
    // sidebar never disappears.
    ShellRoute(
      builder: (context, state, child) =>
          PlainShell(location: state.uri.toString(), child: child),
      routes: [
        // One job in full; the id is in the path so a link to a job opens cold.
        GoRoute(
          path: '/jobs/:id',
          builder: (context, state) =>
              JobDetailsPage(jobId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/scan-progress',
          builder: (context, state) => const StateScanPage(),
        ),
        GoRoute(
          path: '/watchlist',
          builder: (context, state) => const WatchlistPage(),
        ),
        GoRoute(path: '/users', builder: (context, state) => const UsersPage()),
        // Validate the no-website leads by state — WhatsApp and email tabs.
        GoRoute(
          path: '/website-leads/validate',
          builder: (context, state) =>
              NoWebsiteValidationPage(initialTab: state.uri.queryParameters['tab'] == 'email' ? 1 : 0),
        ),
        GoRoute(
          path: '/salesman-stats',
          builder: (context, state) => const SalesmanStatsPage(),
        ),
        GoRoute(
          path: '/salesman-stats/:userId',
          builder: (context, state) => SalesmanContactedLeadsPage(
            userId: state.pathParameters['userId']!,
            salesmanName: state.uri.queryParameters['name'] ?? 'Salesman',
          ),
        ),
        GoRoute(
          path: '/app-update',
          builder: (context, state) => const AppUpdatePage(),
        ),
        GoRoute(
          path: '/clients',
          builder: (context, state) => const ClientsPage(),
        ),
        GoRoute(
          path: '/twilio-test',
          builder: (context, state) => const TwilioTestLeadsPage(),
        ),
        // The lead comes via `extra`; a refreshed tab (no extra) goes back to the list.
        GoRoute(
          path: '/twilio-test/chat',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is TwilioTestLead) return TwilioTestChatPage(lead: extra);
            return const TwilioTestLeadsPage();
          },
        ),
        GoRoute(
          path: '/whatsapp-verified',
          builder: (context, state) => const WhatsAppValidatedArchivePage(),
        ),
        // Legacy/dormant multi-country scan dashboard — still reachable from
        // the handful of old archives that predate the state/city scan engine.
        GoRoute(
          path: '/multi-scan',
          builder: (context, state) => const MultiScanPage(),
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
              return BusinessDetailsPage(lead: extra.lead);
            }
            if (extra is Lead) return BusinessDetailsPage(lead: extra);
            return const SavedBusinessesPage();
          },
        ),
      ],
    ),
  ],
);
