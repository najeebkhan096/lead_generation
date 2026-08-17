import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Home for secondary tools that don't need to be one click away from
/// every session — daily-review tracking and archived scan browsing.
/// Frequent-use pages (Dashboard, Leads, WhatsApp Tool, Sales) stay in the
/// main sidebar; everything here is a deliberate visit, not a glance.
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
                Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Watchlist tracking and archived scan data live here.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: 'Client tracking',
                  items: [
                    _SettingsItem(
                      icon: AppIcons.eye,
                      title: 'Watchlist',
                      subtitle: 'Manually-tracked client businesses, re-scanned on demand for new reviews',
                      onTap: () => context.push('/watchlist'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SettingsSection(
                  title: 'Archived scans',
                  items: [
                    _SettingsItem(
                      icon: AppIcons.inbox,
                      title: 'Excel Archive',
                      subtitle: 'Browse and extract businesses from every Excel-only scan',
                      onTap: () => context.push('/excel-archive'),
                    ),
                    _SettingsItem(
                      icon: AppIcons.shieldCheck,
                      title: 'WhatsApp Verified',
                      subtitle: 'Businesses uploaded after real WhatsApp number validation',
                      onTap: () => context.push('/whatsapp-verified'),
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
