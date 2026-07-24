import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';

class LeadCard extends StatelessWidget {
  const LeadCard({super.key, required this.lead});

  final Lead lead;

  Future<void> _openMaps(BuildContext context) async {
    final ok = await openGoogleMaps(lead.mapsUrl);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No Google Maps link for this business')),
      );
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final ok = await openWhatsApp(lead.whatsAppUrl);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No WhatsApp number for this business')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = lead.badReview.text.trim().isEmpty
        ? 'No review text'
        : lead.badReview.text.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    lead.business,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (lead.rating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, size: 14, color: AppTheme.warn),
                        const SizedBox(width: 4),
                        Text(
                          lead.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            color: AppTheme.warn,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (lead.location.isNotEmpty) lead.location,
                if (lead.address != null && lead.address!.isNotEmpty) lead.address,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (lead.phone != null && lead.phone!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                lead.phone!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.ink,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1★ · ${lead.badReview.date}',
                    style: const TextStyle(
                      color: AppTheme.warn,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    review,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: lead.mapsUrl == null || lead.mapsUrl!.isEmpty
                        ? null
                        : () => _openMaps(context),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Maps'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: lead.whatsAppUrl == null
                        ? null
                        : () => _openWhatsApp(context),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('WhatsApp'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.whatsApp,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
