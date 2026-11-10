import 'package:flutter/material.dart';

import '../design_system/design_system.dart';
import '../../domain/entities/lead.dart';
import '../utils/date_format.dart';

/// Compact summary card for a single saved business, used in the
/// Leads grid. Tapping opens the full details page.
class SavedBusinessCard extends StatelessWidget {
  const SavedBusinessCard({
    super.key,
    required this.lead,
    required this.onTap,
    this.onDelete,
    this.deleting = false,
  });

  final Lead lead;
  final VoidCallback onTap;

  /// `null` hides the delete button (e.g. while its deletion is disallowed).
  final VoidCallback? onDelete;

  /// Shows a spinner in place of the delete button while a delete request
  /// for this card is in flight.
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(lead.savedAt);
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    // hasWhatsApp is only ever true after a real WhatsApp Web check — a
    // stronger signal than just "has a phone number that might work".
    final verified = lead.hasWhatsApp;
    final maybeWhatsApp = !verified && (lead.waLink?.isNotEmpty ?? false);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                alignment: Alignment.center,
                child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primary700)),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lead.business, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    if (lead.category.isNotEmpty) AppBadge(lead.category, tone: AppTone.primary, dense: true),
                  ],
                ),
              ),
              if (onDelete != null)
                AppIconButton(
                  icon: AppIcons.trash,
                  tooltip: 'Delete',
                  size: 30,
                  loading: deleting,
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md + 2),
          if (lead.rating != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(AppIcons.star, size: 14, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Text('${lead.rating}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
          if (lead.phone != null && lead.phone!.isNotEmpty) _InfoRow(icon: AppIcons.phone, text: lead.phone!),
          if (lead.address != null && lead.address!.isNotEmpty) _InfoRow(icon: AppIcons.mapPin, text: lead.address!),
          const Spacer(),
          const SizedBox(height: AppSpace.sm + 2),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (verified)
                      const AppBadge('Verified', tone: AppTone.success, icon: AppIcons.checkCircle, dense: true)
                    else if (maybeWhatsApp)
                      const AppBadge('WhatsApp', tone: AppTone.neutral, icon: AppIcons.chat, dense: true),
                  ],
                ),
              ),
              if (addedOn != null) Text(addedOn, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
