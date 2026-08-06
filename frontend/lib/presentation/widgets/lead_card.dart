import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';

class LeadCard extends StatelessWidget {
  const LeadCard({super.key, required this.lead});

  final Lead lead;

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String? get _whatsAppUrl {
    if (lead.waLink != null && lead.waLink!.isNotEmpty) return lead.waLink;
    final digits = (lead.phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return 'https://wa.me/$digits';
  }

  @override
  Widget build(BuildContext context) {
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    final warm = lead.business.hashCode.isEven;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: warm ? AppTheme.accent100 : AppTheme.sage100,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: warm ? AppTheme.accent700 : AppTheme.sage700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.business,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${lead.category} · ${lead.location}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (lead.rating != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent100,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.star, size: 13, color: AppTheme.accent700),
                      const SizedBox(width: 4),
                      Text(
                        '${lead.rating}',
                        style: const TextStyle(
                          color: AppTheme.accent800,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accent100,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.thumbsDown, size: 13, color: AppTheme.accent700),
                    const SizedBox(width: 6),
                    Text(
                      'Latest 1-star · ${lead.badReview.date}',
                      style: const TextStyle(
                        color: AppTheme.accent700,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  lead.badReview.text.isEmpty
                      ? '(No review text captured)'
                      : lead.badReview.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.ink),
                ),
              ],
            ),
          ),
          if (lead.phone != null && lead.phone!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(AppIcons.phone, size: 16, color: AppTheme.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lead.phone!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                  ),
                ),
              ],
            ),
          ],
          if (lead.website != null && lead.website!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(AppIcons.globe, size: 16, color: AppTheme.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lead.website!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.accent700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: lead.mapsUrl == null || lead.mapsUrl!.isEmpty
                    ? null
                    : () => _open(lead.mapsUrl),
                icon: const Icon(AppIcons.mapPin, size: 16),
                label: const Text('Google Maps'),
              ),
              if (_whatsAppUrl != null)
                FilledButton.icon(
                  onPressed: () => _open(_whatsAppUrl),
                  icon: const Icon(AppIcons.chat, size: 16),
                  label: const Text('WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.sage500,
                    foregroundColor: AppTheme.surface,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: lead.website == null ? null : () => _open(lead.website),
                icon: const Icon(AppIcons.globe, size: 16),
                label: const Text('Website'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: lead.copyDetails));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Details copied')),
                    );
                  }
                },
                icon: const Icon(AppIcons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
