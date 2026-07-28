import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';

/// Full details for a single saved business.
class BusinessDetailsPage extends StatelessWidget {
  const BusinessDetailsPage({super.key, required this.lead});

  final Lead lead;

  Future<void> _launch(
    BuildContext context,
    Future<bool> Function() action,
    String failureMessage,
  ) async {
    final ok = await action();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(lead.dateAdded);

    return Scaffold(
      appBar: AppBar(title: Text(lead.business)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  lead.business,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (lead.rating != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 16, color: AppTheme.warn),
                      const SizedBox(width: 4),
                      Text(
                        lead.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppTheme.warn,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (lead.totalReviews != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${lead.totalReviews})',
                          style: const TextStyle(color: AppTheme.warn, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTheme.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(icon: Icons.category_outlined, label: 'Category', value: lead.category),
                  _DetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: lead.phone,
                    onTap: lead.phone == null
                        ? null
                        : () => _launch(
                              context,
                              () => openPhone(lead.phone),
                              'Could not open dialer',
                            ),
                  ),
                  _DetailRow(
                    icon: Icons.public,
                    label: 'Website',
                    value: lead.website,
                    onTap: lead.website == null
                        ? null
                        : () => _launch(
                              context,
                              () => openWebsite(lead.website),
                              'Could not open website',
                            ),
                  ),
                  _DetailRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: lead.email,
                    onTap: lead.email == null
                        ? null
                        : () => _launch(
                              context,
                              () => openEmail(lead.email),
                              'Could not open email app',
                            ),
                  ),
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Address',
                    value: lead.address,
                    onTap: lead.mapsUrl == null
                        ? null
                        : () => _launch(
                              context,
                              () => openGoogleMaps(lead.mapsUrl),
                              'No Google Maps link for this business',
                            ),
                  ),
                  _DetailRow(icon: Icons.map_outlined, label: 'Location', value: lead.location),
                  _DetailRow(
                    icon: Icons.chat_outlined,
                    label: 'WhatsApp',
                    value: lead.whatsAppUrl,
                    onTap: lead.whatsAppUrl == null
                        ? null
                        : () => _launch(
                              context,
                              () => openWhatsApp(lead.whatsAppUrl),
                              'No phone number for WhatsApp',
                            ),
                  ),
                  _DetailRow(icon: Icons.event_outlined, label: 'Date Added', value: addedOn),
                ],
              ),
            ),
          ),
          if (lead.badReview.text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Flagged Review', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${lead.badReview.stars}★ · ${lead.badReview.date}'
                    '${lead.badReview.reviewer != null ? ' · ${lead.badReview.reviewer}' : ''}',
                    style: const TextStyle(
                      color: AppTheme.warn,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(lead.badReview.text, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.slate),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              hasValue ? value! : 'Not available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: hasValue && onTap != null ? AppTheme.accent : null,
                    fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null || !hasValue) return content;
    return InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: content);
  }
}
