import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/whatsapp_link.dart';

/// One extracted business, rendered from a raw archive row map (the same
/// {header: value} shape every archive viewer/leads page works with —
/// see LEAD_COLUMNS in backend/src/services/exportService.js). Used by
/// excel_archive_page.dart, whatsapp_validated_archive_page.dart,
/// excel_leads_page.dart, and whatsapp_verified_leads_page.dart so the
/// card layout — including the two big action buttons — stays identical
/// everywhere a business shows up.
class BusinessRowCard extends StatelessWidget {
  const BusinessRowCard({
    super.key,
    required this.row,
    this.badgeLabel,
    this.categoryLabel,
    this.footerLabel,
  });

  final Map<String, dynamic> row;

  /// Small label above the business name, e.g. "WhatsApp Verified".
  final String? badgeLabel;

  /// Category + source-file line shown under the name — used by the
  /// combined "browse by category" pages, which mix rows from many
  /// archives together (a single-archive viewer's tab already names the
  /// category, so it passes this as null).
  final String? categoryLabel;

  /// Small label under the address, e.g. the source archive's file name.
  final String? footerLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = (row['Business Name'] ?? '').toString();
    final phone = (row['Phone'] ?? '').toString();
    final rating = (row['Rating'] ?? '').toString();
    final address = (row['Address'] ?? '').toString();
    final review = (row['Review'] ?? '').toString();
    final mapsUrl = (row['Maps URL'] ?? '').toString();
    final waUrl = whatsAppUrlFor(row, phone);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: badgeLabel != null ? t.sage.withValues(alpha: 0.35) : t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badgeLabel != null) ...[
            Row(
              children: [
                Icon(AppIcons.circleCheck, size: 13, color: t.sageDeep),
                const SizedBox(width: 5),
                Text(
                  badgeLabel!,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: t.sageDeep),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? 'Unnamed business' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              if (rating.isNotEmpty) ...[
                Icon(AppIcons.star, size: 13, color: t.accentText),
                const SizedBox(width: 3),
                Text(rating, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentText)),
              ],
            ],
          ),
          if (categoryLabel != null && categoryLabel!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              categoryLabel!,
              style: TextStyle(fontSize: 11.5, color: t.faint, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(address, style: TextStyle(fontSize: 12, color: t.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (footerLabel != null && footerLabel!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(footerLabel!, style: TextStyle(fontSize: 10.5, color: t.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(AppIcons.phone, size: 12, color: t.subtle),
                const SizedBox(width: 5),
                Text(phone, style: TextStyle(fontSize: 12.5, color: t.subtle, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (review.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review, style: Theme.of(context).textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (waUrl != null || mapsUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (waUrl != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => launchUrl(Uri.parse(waUrl)),
                      style: FilledButton.styleFrom(
                        backgroundColor: t.sage,
                        foregroundColor: t.onFill,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(AppIcons.chat, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                if (waUrl != null && mapsUrl.isNotEmpty) const SizedBox(width: 10),
                if (mapsUrl.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(mapsUrl)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(AppIcons.mapPin, size: 18),
                      label: const Text('Review'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
