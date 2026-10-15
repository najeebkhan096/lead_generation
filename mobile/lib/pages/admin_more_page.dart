import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_data.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/admin_analytics.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/page_header.dart';
import 'admin_payouts_page.dart';
import 'admin_users_page.dart';
import '../services/admin_repository.dart';
import 'main_navigation_page.dart';
import 'settings_page.dart';

/// Account and admin tools that are not a main tab.
class AdminMorePage extends StatelessWidget {
  const AdminMorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AdminScope.of(context);
    final snap = data.snapshot;
    final user = FirebaseAuth.instance.currentUser;
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final pending = snap.pendingApprovals;
    final due = snap.overall.payablePkr;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(title: 'More', subtitle: 'Accounts, payouts and settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                AdminCard(
                  child: Row(
                    children: [
                      PersonAvatar(name: user?.displayName ?? user?.email ?? 'Admin', photoUrl: user?.photoURL, size: 48),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.displayName ?? 'Administrator', style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (user?.email != null) Text(user!.email!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const StatusPill(label: 'Admin', tone: Tone.accent),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _MenuRow(
                  icon: AppIcons.users,
                  title: 'Users & access',
                  subtitle: pending > 0 ? '$pending awaiting approval' : 'Approve accounts, change roles',
                  badge: pending > 0 ? '$pending' : null,
                  onTap: () => pushAdminPage(context, const AdminUsersPage()),
                ),
                const SizedBox(height: 10),
                _MenuRow(
                  icon: AppIcons.wallet,
                  title: 'Payouts',
                  subtitle: due > 0 ? '${formatPkr(due)} due to salesmen' : 'Settle salesman earnings',
                  onTap: () => pushAdminPage(context, const AdminPayoutsPage()),
                ),
                const SizedBox(height: 10),
                _MenuRow(
                  icon: AppIcons.history,
                  title: 'Start fresh from today',
                  subtitle: snap.overall.archived > 0
                      ? '${snap.overall.archived} earlier ${snap.overall.archived == 1 ? 'order' : 'orders'} not counted'
                      : 'Stop counting older payments, keep every client',
                  onTap: () => _freshStart(context, data),
                ),
                const SizedBox(height: 10),
                _MenuRow(
                  icon: AppIcons.star,
                  title: 'Leads workspace',
                  subtitle: 'Browse verified leads and outreach like a salesman',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MainNavigationPage())),
                ),
                const SizedBox(height: 10),
                _MenuRow(
                  icon: AppIcons.settings,
                  title: 'Appearance & app',
                  subtitle: 'Theme and app settings',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmAdminAction(
                      context,
                      title: 'Sign out?',
                      message: 'You will need to sign in again to manage sales.',
                      confirmLabel: 'Sign out',
                      destructive: true,
                    );
                    if (ok) await AuthService().signOut();
                  },
                  icon: Icon(AppIcons.logOut, size: 18, color: t.danger),
                  label: Text('Sign out', style: TextStyle(color: t.danger)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Archives the payments of every sale created before today. Previews the
/// count first, asks to confirm, and never deletes anything.
Future<void> _freshStart(BuildContext context, AdminData data) async {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final archived = data.snapshot.overall.archived;

  ArchiveResult preview;
  try {
    preview = await data.archivePayments(before: startOfToday);
  } catch (e) {
    if (context.mounted) showAdminError(context, e);
    return;
  }
  if (!context.mounted) return;

  if (preview.matched == 0) {
    if (archived == 0) {
      showAdminMessage(context, 'No earlier orders — everything already counts from today.');
      return;
    }
    final undo = await confirmAdminAction(
      context,
      title: 'Already started fresh',
      message: '$archived earlier ${archived == 1 ? 'order is' : 'orders are'} excluded from payments. Count them again?',
      confirmLabel: 'Count again',
    );
    if (undo && context.mounted) await _run(context, data, startOfToday, restore: true);
    return;
  }

  final ok = await confirmAdminAction(
    context,
    title: 'Start fresh from today?',
    message: '${preview.matched} earlier ${preview.matched == 1 ? 'order' : 'orders'} will stop counting in payouts, billing and profit.\n\n'
        'Clients and every detail are kept, nothing is deleted, and you can undo this.',
    confirmLabel: 'Start fresh',
  );
  if (ok && context.mounted) await _run(context, data, startOfToday);
}

Future<void> _run(BuildContext context, AdminData data, DateTime before, {bool restore = false}) async {
  try {
    final result = await data.archivePayments(
      before: restore ? before.add(const Duration(days: 1)) : before,
      restore: restore,
      apply: true,
    );
    if (!context.mounted) return;
    showAdminMessage(
      context,
      restore ? '${result.updated} orders count again' : 'Fresh start: ${result.updated} earlier orders no longer counted',
    );
  } catch (e) {
    if (context.mounted) showAdminError(context, e);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.title, required this.subtitle, required this.onTap, this.badge});

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return AdminCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconHolder(icon: icon, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall?.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          if (badge != null) ...[StatusPill(label: badge!, tone: Tone.accent), const SizedBox(width: 8)],
          Icon(AppIcons.chevronRight, size: 18, color: t.faint),
        ],
      ),
    );
  }
}
