import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../services/open_links.dart';
import '../services/paged_query.dart';
import '../theme/app_theme.dart';
import '../widgets/lead_collection_page.dart';

/// Which validation a verified-leads list is the output of.
enum VerifiedKind {
  whatsapp(
    collection: 'whatsappLeads',
    title: 'WhatsApp',
    emptyHint: 'Businesses with a confirmed WhatsApp number will land here',
  ),
  email(
    collection: 'emailLeads',
    title: 'Email',
    emptyHint: 'Businesses with a verified contact email will land here',
  );

  const VerifiedKind({required this.collection, required this.title, required this.emptyHint});

  /// Firestore collection the web console's validators write to.
  final String collection;
  final String title;
  final String emptyHint;
}

class _Row {
  const _Row(this.lead, this.sourceType);

  final Lead lead;

  /// `review` (1-star) or `website` (no website) — which signal the lead
  /// was found by. Absent on documents written before the field existed.
  final String? sourceType;
}

/// A verified lead list — the output of one of the two validators.
///
/// Reads the dedicated collection straight from Firestore, a page at a time
/// (see [LeadCollectionPage]), so a lead the web console validates shows up
/// here after a pull-to-refresh, without any archive step.
class VerifiedLeadsPage extends StatelessWidget {
  const VerifiedLeadsPage({super.key, required this.kind});

  final VerifiedKind kind;

  bool get _isWhatsApp => kind == VerifiedKind.whatsapp;

  @override
  Widget build(BuildContext context) {
    return LeadCollectionPage<_Row>(
      title: '${kind.title} leads',
      noun: 'business',
      headerIcon: _isWhatsApp ? AppIcons.chat : AppIcons.mail,
      searchHint: 'Search ${kind.title.toLowerCase()} leads...',
      emptyIcon: _isWhatsApp ? AppIcons.chat : AppIcons.mail,
      emptyTitle: 'No ${kind.title} leads yet',
      emptyBody: 'Validate leads from the web console and they appear here.',
      emptySubtitle: kind.emptyHint,
      filters: const [
        (label: 'All signals', value: null),
        (label: '1-star', value: 'review'),
        (label: 'No website', value: 'website'),
      ],
      controllerFor: (sourceType) => PagedQueryController<_Row>(
        segments: [
          (category) {
            Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(kind.collection);
            if (sourceType != null) q = q.where('sourceType', isEqualTo: sourceType);
            if (category != null) q = q.where('category', isEqualTo: category);
            return q.orderBy('updatedAt', descending: true);
          },
        ],
        map: (doc) => _Row(Lead.fromDoc(doc), doc.data()['sourceType'] as String?),
      ),
      // Listed by `updatedAt` (when it was verified / last re-checked).
      dateOf: (row) => row.lead.updatedAt ?? row.lead.createdAt,
      searchText: (r) =>
          '${r.lead.business} ${r.lead.location} ${r.lead.phone ?? ''} ${r.lead.email ?? ''} ${r.lead.category}'
              .toLowerCase(),
      categoryOf: (r) => r.lead.category,
      loadCategories: LeadRepository().fetchCategoryNames,
      itemBuilder: (context, row) => _VerifiedCard(row: row, kind: kind),
    );
  }
}

class _VerifiedCard extends StatelessWidget {
  const _VerifiedCard({required this.row, required this.kind});

  final _Row row;
  final VerifiedKind kind;

  String? get _waUrl {
    final l = row.lead;
    if (l.waLink != null && l.waLink!.isNotEmpty) return l.waLink;
    final digits = (l.phone ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : 'https://wa.me/$digits';
  }

  Future<void> _act(BuildContext context, Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = row.lead;
    final isWhatsApp = kind == VerifiedKind.whatsapp;
    final contact = isWhatsApp ? l.phone : l.email;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusCard)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.business,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (row.sourceType != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accentTint,
                    borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
                  ),
                  child: Text(
                    row.sourceType == 'review' ? '1-star' : 'No website',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.accentTextStrong),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l.category, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          if (contact != null && contact.isNotEmpty)
            Row(
              children: [
                Icon(isWhatsApp ? AppIcons.chat : AppIcons.mail, size: 15, color: t.subtle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    contact,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (l.address != null && l.address!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(AppIcons.mapPin, size: 15, color: t.subtle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.address!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isWhatsApp)
                FilledButton.icon(
                  onPressed: () => _act(context, () => openWhatsApp(_waUrl), 'Could not open WhatsApp'),
                  icon: const Icon(AppIcons.chat, size: 16),
                  label: const Text('WhatsApp'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _act(context, () => openEmail(l.email), 'Could not open your email app'),
                  icon: const Icon(AppIcons.mail, size: 16),
                  label: const Text('Email'),
                ),
              if (l.phone != null && l.phone!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _act(context, () => openPhone(l.phone), 'Could not open the dialer'),
                  icon: const Icon(AppIcons.phone, size: 16),
                  label: const Text('Call'),
                ),
              if (l.mapsUrl != null && l.mapsUrl!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _act(context, () => openGoogleMaps(l.mapsUrl), 'Could not open Maps'),
                  icon: const Icon(AppIcons.mapPin, size: 16),
                  label: const Text('Maps'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
