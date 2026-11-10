import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/design_system.dart';

/// Everything that isn't the core flow (Scan → Leads → Validate →
/// Verified). Kept one tap away but out of the main navigation:
/// the WhatsApp connection the validator needs, the extra business tools,
/// and access management.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'More',
      subtitle: 'Connections, extra tools and access.',
      children: [
        ResponsiveGrid(
          minTileWidth: 380,
          spacing: AppSpace.xl,
          evenRows: false,
          children: [
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
                  subtitle:
                      'Workbooks uploaded after validating an Excel Archive',
                  onTap: () => context.push('/whatsapp-verified'),
                ),
              ],
            ),
            _SettingsSection(
              title: 'More lead lists',
              items: [
                _SettingsItem(
                  icon: AppIcons.globe,
                  title: 'Website leads',
                  subtitle: 'Businesses Google Maps lists with no website',
                  onTap: () => context.go('/website-leads'),
                ),
                _SettingsItem(
                  icon: AppIcons.mail,
                  title: 'Email leads',
                  subtitle: 'Business emails published on their websites',
                  onTap: () => context.go('/email-leads'),
                ),
              ],
            ),
            _SettingsSection(
              title: 'Business tools',
              items: [
                _SettingsItem(
                  icon: AppIcons.chat,
                  title: 'Twilio test leads',
                  subtitle:
                      'Add throwaway leads to try WhatsApp / SMS outreach',
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
                  subtitle:
                      'Contacts per salesman, per day, against each daily limit',
                  onTap: () => context.push('/salesman-stats'),
                ),
                _SettingsItem(
                  icon: AppIcons.download,
                  title: 'App update',
                  subtitle:
                      'Minimum build, latest APK and the update message for the phones',
                  onTap: () => context.push('/app-update'),
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
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppTheme.divider),
            items[i],
          ],
        ],
      ),
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
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        child: Row(
          children: [
            IconTile(icon, size: 36),
            const SizedBox(width: AppSpace.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: text.bodySmall),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, size: 16, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
