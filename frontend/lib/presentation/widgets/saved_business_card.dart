import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../utils/date_format.dart';

/// Compact summary card for a single saved business, used in the
/// Leads grid. Tapping opens the full details page.
class SavedBusinessCard extends StatelessWidget {
  const SavedBusinessCard({super.key, required this.lead, required this.onTap});

  final Lead lead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(lead.savedAt);
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    final warm = lead.business.hashCode.isEven;
    // hasWhatsApp is only ever true after a real WhatsApp Web check — a
    // stronger signal than just "has a phone number that might work".
    final verified = lead.hasWhatsApp;
    final maybeWhatsApp = !verified && (lead.waLink?.isNotEmpty ?? false);

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: warm ? AppTheme.accent100 : AppTheme.sage100,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: warm ? AppTheme.accent700 : AppTheme.sage700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.business,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _CategoryChip(category: lead.category),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (lead.rating != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(AppIcons.star, size: 14, color: AppTheme.accent),
                      const SizedBox(width: 6),
                      Text(
                        '${lead.rating}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              if (lead.phone != null && lead.phone!.isNotEmpty)
                _InfoRow(icon: AppIcons.phone, text: lead.phone!),
              if (lead.address != null && lead.address!.isNotEmpty)
                _InfoRow(icon: AppIcons.mapPin, text: lead.address!),
              const Spacer(),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (verified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.sage500,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(AppIcons.checkCircle, size: 12, color: AppTheme.surface),
                          const SizedBox(width: 4),
                          const Text(
                            'Verified',
                            style: TextStyle(
                              color: AppTheme.surface,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (maybeWhatsApp)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.sage100,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(AppIcons.chat, size: 12, color: AppTheme.sage700),
                          const SizedBox(width: 4),
                          const Text(
                            'WhatsApp',
                            style: TextStyle(
                              color: AppTheme.sage700,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  if (addedOn != null)
                    Text(
                      addedOn,
                      style: const TextStyle(fontSize: 11, color: AppTheme.faint),
                    ),
                ],
              ),
            ],
          ),
        ),
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
          Icon(icon, size: 13, color: AppTheme.faint),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent100,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        category,
        style: const TextStyle(
          color: AppTheme.accent800,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
