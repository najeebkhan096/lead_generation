import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/lead_labels.dart';

/// A verified lead plus the validation fact that lives on the verified
/// document itself (not on the source [Lead]).
class VerifiedLead {
  const VerifiedLead({
    required this.lead,
    this.verifiedAt,
    this.contactedAt,
    this.dealDoneAt,
  });

  final Lead lead;

  /// When the WhatsApp check confirmed it.
  final DateTime? verifiedAt;

  /// When a salesperson marked it contacted (null while it is a New lead).
  final DateTime? contactedAt;

  /// When it was marked a deal done (null unless it is one).
  final DateTime? dealDoneAt;

  /// The verified date to show: when it was confirmed, else the last write.
  DateTime? get shownDate => verifiedAt ?? lead.updatedAt ?? lead.createdAt;

  /// Anything past New (contacted, and the later deal stages) is "contacted".
  bool get isContacted => lead.status != LeadStatus.lead;

  /// A contacted lead the salesman has closed as a deal.
  bool get isDealDone => lead.status == LeadStatus.dealDone;

  /// Reads the WhatsApp check off a `whatsappLeads` document ([data]); the
  /// shared lead fields come from [lead].
  factory VerifiedLead.fromData(Lead lead, Map<String, dynamic> data) {
    final checked = data['whatsAppCheckedAt'];
    return VerifiedLead(
      lead: lead,
      verifiedAt: checked is Timestamp ? checked.toDate() : null,
      contactedAt: data['contactedAt'] is Timestamp ? (data['contactedAt'] as Timestamp).toDate() : null,
      dealDoneAt: data['dealDoneAt'] is Timestamp ? (data['dealDoneAt'] as Timestamp).toDate() : null,
    );
  }
}

/// How the card reaches a lead. The real launchers by default; tests pass
/// fakes so a tap does not need a phone.
class LeadActions {
  const LeadActions({
    this.whatsapp = openWhatsApp,
    this.maps = openGoogleMaps,
  });

  final Future<bool> Function(String? url) whatsapp;
  final Future<bool> Function(String? url) maps;
}

/// One verified lead, as a flat bordered card:
///
///   [initial] Business name                  [1-star]
///             Category · State
///   ✓ On WhatsApp · Oct 12, 2026 · 3:45 PM      (verified / contacted chip)
///   ┌ +1 385 789 5802 ───────────────────┐
///   └ the contact, big ──────────────────┘
///   address · rating
///   │ the 1-star review that made it a lead
///   [ WhatsApp ]  (map)
class VerifiedLeadCard extends StatelessWidget {
  const VerifiedLeadCard({
    super.key,
    required this.item,
    this.onWhatsApp,
    this.onMoveToNew,
    this.onOpen,
    this.actions = const LeadActions(),
  });

  final VerifiedLead item;
  final LeadActions actions;

  /// Opens WhatsApp for the lead. The owner decides how: a New lead is marked
  /// Contacted first, and a refusal there keeps WhatsApp closed. Without it,
  /// the card opens WhatsApp itself.
  final Future<void> Function()? onWhatsApp;

  /// Moves a contacted lead back to New (button shown only when set).
  final Future<void> Function()? onMoveToNew;

  /// Opens the lead's detail page. Tapping the business name does it.
  final VoidCallback? onOpen;

  Future<void> _act(BuildContext context, Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  Future<void> _whatsApp(BuildContext context) async {
    final owner = onWhatsApp;
    if (owner != null) return owner();
    await _act(context, () => actions.whatsapp(item.lead.whatsAppUrl), 'Could not open WhatsApp');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final l = item.lead;
    final contact = l.phone;
    final verified = formatDateTime(item.shownDate);
    final category = cleanCategory(l.category);
    final where = [category, if (l.location.trim().isNotEmpty) l.location.trim()].join(' · ');
    final rating = ratingLabel(l.rating, l.totalReviews);
    final review = l.badReview;
    final showReview = review.text.trim().isNotEmpty || review.date != 'Unknown';
    final initial = l.business.trim().isEmpty ? '?' : String.fromCharCode(l.business.trim().runes.first).toUpperCase();

    Widget detail(IconData icon, String value, {int lines = 1}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: t.faint)),
              const SizedBox(width: 10),
              Expanded(child: Text(value, style: text.bodySmall?.copyWith(color: t.subtle), maxLines: lines, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );

    Widget chip(IconData icon, String label, {required Color background, required Color foreground}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusCard)),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radius)),
            child:
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accentTint,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Text(initial, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: t.accentText)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.business, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(where, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (verified != null || item.isContacted) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (verified != null)
                  chip(
                    AppIcons.circleCheck,
                    'On WhatsApp · $verified',
                    background: t.sageTint,
                    foreground: t.sageText,
                  ),
                if (item.isContacted)
                  chip(
                    AppIcons.handshake,
                    [
                      l.status.label,
                      if (formatDateTime(item.contactedAt) != null) formatDateTime(item.contactedAt)!,
                    ].join(' · '),
                    background: t.accentTint,
                    foreground: t.accentTextStrong,
                  ),
              ],
            ),
          ],
          if (contact != null && contact.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.neutralTint,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(AppIcons.chat, size: 17, color: t.accentText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          contact,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.ink),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (l.address != null && l.address!.isNotEmpty) detail(AppIcons.mapPin, l.address!, lines: 2),
          if (rating != null) detail(AppIcons.star, rating),
          if (showReview) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: t.neutralTint,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border(left: BorderSide(color: t.accent, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      '1-star review',
                      if (review.date != 'Unknown' && review.date.isNotEmpty) review.date,
                      if ((review.reviewer ?? '').isNotEmpty) 'by ${review.reviewer}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.subtle),
                  ),
                  if (review.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('“${review.text.trim()}”', style: text.bodyMedium?.copyWith(color: t.ink), maxLines: 4, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _whatsApp(context),
                  icon: const Icon(AppIcons.chat, size: 17),
                  label: const Text('WhatsApp'),
                ),
              ),
              if (l.mapsUrl != null && l.mapsUrl!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: t.sage, foregroundColor: t.onFill),
                    onPressed: () => _act(context, () => actions.maps(l.mapsUrl), 'Could not open Maps'),
                    icon: const Icon(AppIcons.mapPin, size: 17),
                    label: const Text('Map'),
                  ),
                ),
              ],
            ],
          ),
          if (item.isContacted && onMoveToNew != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onMoveToNew!(),
                icon: const Icon(AppIcons.refresh, size: 16),
                label: const Text('Move to New'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
