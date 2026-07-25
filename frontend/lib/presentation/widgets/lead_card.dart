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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lead.business,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
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
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${lead.rating} ★',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warnSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Latest 1-star · ${lead.badReview.date}',
                  style: TextStyle(
                    color: AppTheme.warn,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  lead.badReview.text.isEmpty
                      ? '(No review text captured)'
                      : lead.badReview.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.ink,
                      ),
                ),
              ],
            ),
          ),
          if (lead.phone != null && lead.phone!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 18, color: AppTheme.slate),
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
            Text(
              lead.website!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.accent,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: lead.mapsUrl == null || lead.mapsUrl!.isEmpty
                    ? null
                    : () => _open(lead.mapsUrl),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Google Maps'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_whatsAppUrl != null)
                FilledButton.icon(
                  onPressed: () => _open(_whatsAppUrl),
                  icon: const Icon(Icons.chat, size: 16),
                  label: const Text('WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: lead.website == null ? null : () => _open(lead.website),
                icon: const Icon(Icons.language, size: 16),
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
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
