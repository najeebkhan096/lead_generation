import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Everything that isn't the core flow (Scan → Leads → Validate →
/// Verified). Kept one tap away but out of the main navigation:
/// the WhatsApp connection the validator needs, the extra business tools,
/// and access management.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              children: [
                Text('More', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Connections, extra tools and access. The main flow lives in the sidebar.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: 'Validation',
                  items: [
                    _SettingsItem(
                      icon: AppIcons.chat,
                      title: 'WhatsApp connection',
                      subtitle: 'Link WhatsApp Web (QR) — needed to check numbers',
                      onTap: () => context.go('/whatsapp'),
                    ),
                    _SettingsItem(
                      icon: AppIcons.shieldCheck,
                      title: 'WhatsApp Verified archives',
                      subtitle: 'Workbooks uploaded after validating an Excel Archive',
                      onTap: () => context.push('/whatsapp-verified'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SettingsSection(
                  title: 'Business tools',
                  items: [
                    _SettingsItem(
                      icon: AppIcons.chat,
                      title: 'Twilio test leads',
                      subtitle: 'Add throwaway leads to try WhatsApp / SMS outreach',
                      onTap: () => context.push('/twilio-test'),
                    ),
                    _SettingsItem(
                      icon: AppIcons.tag,
                      title: 'Sales',
                      subtitle: 'Orders, payouts and client review scans',
                      onTap: () => context.go('/sales'),
                    ),
                    _SettingsItem(
                      icon: AppIcons.target,
                      title: 'Watchlist',
                      subtitle: 'Re-scan chosen businesses for new 1-star reviews',
                      onTap: () => context.push('/watchlist'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SettingsSection(
                  title: 'Access',
                  items: [
                    _SettingsItem(
                      icon: AppIcons.users,
                      title: 'Users',
                      subtitle: 'Approve salespeople for the mobile app',
                      onTap: () => context.push('/users'),
                    ),
                    _SettingsItem(
                      icon: AppIcons.barChart,
                      title: 'Salesman stats',
                      subtitle: 'Contacts per salesman, per day, against each daily limit',
                      onTap: () => context.push('/salesman-stats'),
                    ),
                    _SettingsItem(
                      icon: AppIcons.store,
                      title: 'Clients',
                      subtitle: 'Business names and their Google Maps links',
                      onTap: () => context.push('/clients'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.faint),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: AppTheme.neutral200),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                items[i],
                if (i < items.length - 1) const Divider(height: 1, color: AppTheme.neutral200),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: AppTheme.accent700),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.faint)),
                ],
              ),
            ),
            const Icon(AppIcons.chevronRight, size: 18, color: AppTheme.faint),
          ],
        ),
      ),
    );
  }
}
