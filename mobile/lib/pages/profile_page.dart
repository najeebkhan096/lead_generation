import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/auth_service.dart';
import '../services/lead_repository.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import 'search_history_page.dart';
import 'settings_page.dart';

const _supportEmail = 'najeebkhan.uae.096@gmail.com';
const _appVersion = '1.0.0';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                title: 'My profile',
                subtitle: 'Your account and progress',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityCard(user: user),
                    const SizedBox(height: 16),
                    const _StatsRow(),
                    const SizedBox(height: 28),
                    _ProfileItem(
                      icon: AppIcons.history,
                      label: 'Search History',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SearchHistoryPage()),
                      ),
                    ),
                    _ProfileItem(
                      icon: AppIcons.settings,
                      label: 'App Settings',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                    ),
                    _ProfileItem(
                      icon: AppIcons.help,
                      label: 'Help & Support',
                      onTap: () => _showHelpSheet(context),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmSignOut(context),
                        icon: Icon(AppIcons.logOut,
                            size: 18, color: context.tokens.danger),
                        label: Text('Sign Out',
                            style: TextStyle(color: context.tokens.danger)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: context.tokens.accentDeep
                                  .withValues(alpha: 0.4),
                              width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        final t = sheetContext.tokens;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text('Help & support',
                      style: Theme.of(sheetContext).textTheme.headlineSmall),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: t.accentTint,
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(AppIcons.mail, size: 19, color: t.accentText),
                  ),
                  title: const Text('Email us'),
                  subtitle: Text(_supportEmail,
                      style: Theme.of(sheetContext).textTheme.bodySmall),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await openEmail(_supportEmail);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Could not open your mail app')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: t.neutralTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(AppIcons.info, size: 19, color: t.subtle),
                  ),
                  title: const Text('About'),
                  subtitle: Text('LeadFinder Mobile v$_appVersion',
                      style: Theme.of(sheetContext).textTheme.bodySmall),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService().signOut();
    }
  }
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: t.accentTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: t.accentText),
        ),
        title: Text(label),
        trailing: Icon(AppIcons.chevronRight, size: 18, color: t.faint),
        onTap: onTap,
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: t.sageTintStrong,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 34,
              backgroundColor: t.sageTint,
              backgroundImage:
                  user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              child: user?.photoURL == null
                  ? Icon(AppIcons.user, size: 30, color: t.sageText)
                  : null,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? 'Anonymous User',
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live pipeline numbers straight from the leads stream.
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return StreamBuilder<List<Lead>>(
      stream: LeadRepository().getLeadsStream(),
      builder: (context, snapshot) {
        final leads = snapshot.data ?? const <Lead>[];
        final inProgress = leads
            .where((l) =>
                l.status == LeadStatus.contacted ||
                l.status == LeadStatus.booked)
            .length;
        final won =
            leads.where((l) => l.status == LeadStatus.dealDone).length;

        return Row(
          children: [
            _Stat(
              value: '${leads.length}',
              label: 'Leads',
              background: t.neutralTint,
              foreground: t.subtle,
            ),
            const SizedBox(width: 10),
            _Stat(
              value: '$inProgress',
              label: 'In progress',
              background: t.accentTint,
              foreground: t.accentTextStrong,
            ),
            const SizedBox(width: 10),
            _Stat(
              value: '$won',
              label: 'Deals won',
              background: t.sageTint,
              foreground: t.sageTextStrong,
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String value;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
