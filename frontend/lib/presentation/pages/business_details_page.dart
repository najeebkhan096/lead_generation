import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../utils/date_format.dart';

/// Full details for a single saved business.
class BusinessDetailsPage extends StatelessWidget {
  const BusinessDetailsPage({super.key, required this.lead});

  final Lead lead;

  String? get _whatsAppUrl {
    if (lead.waLink != null && lead.waLink!.isNotEmpty) return lead.waLink;
    final digits = (lead.phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return 'https://wa.me/$digits';
  }

  Future<void> _open(BuildContext context, String? url, String failureMessage) async {
    final uri = url == null ? null : Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(lead.savedAt);

    return Scaffold(
      appBar: AppBar(title: Text(lead.business)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F4F8), Color(0xFFE8F5F3)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        lead.business,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (lead.rating != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${lead.rating} ★'
                          '${lead.totalReviews != null ? ' (${lead.totalReviews})' : ''}',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.line),
                  ),
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
                            : () => _open(context, 'tel:${lead.phone}', 'Could not open dialer'),
                      ),
                      _DetailRow(
                        icon: Icons.language,
                        label: 'Website',
                        value: lead.website,
                        onTap: lead.website == null
                            ? null
                            : () => _open(context, lead.website, 'Could not open website'),
                      ),
                      _DetailRow(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: lead.email,
                        onTap: lead.email == null
                            ? null
                            : () => _open(context, 'mailto:${lead.email}', 'Could not open email app'),
                      ),
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        label: 'Address',
                        value: lead.address,
                        onTap: lead.mapsUrl == null
                            ? null
                            : () => _open(context, lead.mapsUrl, 'No Google Maps link for this business'),
                      ),
                      _DetailRow(icon: Icons.map_outlined, label: 'Location', value: lead.location),
                      _DetailRow(
                        icon: Icons.chat_outlined,
                        label: 'WhatsApp',
                        value: _whatsAppUrl,
                        onTap: _whatsAppUrl == null
                            ? null
                            : () => _open(context, _whatsAppUrl, 'No phone number for WhatsApp'),
                      ),
                      _DetailRow(icon: Icons.event_outlined, label: 'Date Added', value: addedOn),
                    ],
                  ),
                ),
                if (lead.badReview.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Flagged Review', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.warnSoft,
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
                        const SizedBox(height: 6),
                        Text(lead.badReview.text, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
