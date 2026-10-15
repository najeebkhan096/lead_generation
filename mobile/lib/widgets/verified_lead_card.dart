import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/lead_labels.dart';
import '../utils/outreach_email.dart';

/// Which validator a verified lead came from.
enum VerifiedChannel { whatsapp, email }

/// A verified lead plus the validation facts that live on the verified
/// document itself (not on the source [Lead]).
class VerifiedLead {
  const VerifiedLead({
    required this.lead,
    required this.channel,
    this.sourceType,
    this.verifiedAt,
    this.contactedAt,
    this.emailSource,
    this.emailFoundOn,
    this.extraEmails = 0,
  });

  final Lead lead;
  final VerifiedChannel channel;

  /// `review` (1-star) or `website` (no website) — which signal the lead
  /// was found by. Absent on documents written before the field existed.
  final String? sourceType;

  /// When the validator confirmed it (`whatsAppCheckedAt` / `emailCheckedAt`).
  final DateTime? verifiedAt;

  /// When a salesperson marked it contacted (null while it is a New lead).
  final DateTime? contactedAt;
  final String? emailSource;
  final String? emailFoundOn;

  /// Other addresses found for this business besides [Lead.email].
  final int extraEmails;

  /// The verified date to show: when it was confirmed, else the last write.
  DateTime? get shownDate => verifiedAt ?? lead.updatedAt ?? lead.createdAt;

  /// Anything past New (contacted, and the later deal stages) is "contacted".
  bool get isContacted => lead.status != LeadStatus.lead;

  /// Reads the validator's own fields off a `whatsappLeads` / `emailLeads`
  /// document ([data]); the shared lead fields come from [lead].
  factory VerifiedLead.fromData(Lead lead, Map<String, dynamic> data, VerifiedChannel channel) {
    final checked = data[channel == VerifiedChannel.whatsapp ? 'whatsAppCheckedAt' : 'emailCheckedAt'];
    final emails = data['emails'];
    return VerifiedLead(
      lead: lead,
      channel: channel,
      sourceType: data['sourceType'] as String?,
      verifiedAt: checked is Timestamp ? checked.toDate() : null,
      contactedAt: data['contactedAt'] is Timestamp ? (data['contactedAt'] as Timestamp).toDate() : null,
      emailSource: data['emailSource'] as String?,
      emailFoundOn: data['emailFoundOn'] as String?,
      extraEmails: emails is List && emails.length > 1 ? emails.length - 1 : 0,
    );
  }
}

/// How the card reaches a lead. The real launchers by default; tests pass
/// fakes so a tap does not need a phone.
class LeadActions {
  const LeadActions({
    this.whatsapp = openWhatsApp,
    this.email = openEmail,
    this.phone = openPhone,
    this.maps = openGoogleMaps,
    this.website = openWebsite,
  });

  final Future<bool> Function(String? url) whatsapp;
  final Future<bool> Function(String? address, {String? subject, String? body}) email;
  final Future<bool> Function(String? number) phone;
  final Future<bool> Function(String? url) maps;
  final Future<bool> Function(String? url) website;
}

/// One verified lead, as a flat bordered card:
///
///   [initial] Business name                  [1-star]
///             Category · State
///   ✓ On WhatsApp · Oct 12, 2026 · 3:45 PM      (verified / contacted chip)
///   ┌ +1 385 789 5802 ───────────────────┐
///   └ the contact, big ──────────────────┘
///   address · website · rating
///   │ the 1-star review that made it a lead
///   [ WhatsApp ]  (call) (site) (map)
class VerifiedLeadCard extends StatelessWidget {
  const VerifiedLeadCard({
    super.key,
    required this.item,
    this.onContacted,
    this.onMoveToNew,
    this.actions = const LeadActions(),
  });

  final VerifiedLead item;
  final LeadActions actions;

  /// Called once a contact action (WhatsApp / Email / Call) has opened, for a
  /// lead that is still New — the owner moves it to Contacted.
  final Future<void> Function()? onContacted;

  /// Moves a contacted lead back to New (button shown only when set).
  final Future<void> Function()? onMoveToNew;

  bool get _isWhatsApp => item.channel == VerifiedChannel.whatsapp;

  String? get _waUrl => item.lead.whatsAppUrl;

  /// Which pitch this lead gets (see outreach_email.dart).
  LeadSignal get _signal => signalFor(sourceType: item.sourceType, reviewText: item.lead.badReview.text);

  Future<void> _act(BuildContext context, Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  /// A way of contacting the lead: on success, a New lead becomes Contacted.
  Future<void> _contact(BuildContext context, Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
    } else if (!item.isContacted) {
      await onContacted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final l = item.lead;
    final contact = _isWhatsApp ? l.phone : l.email;
    final verified = formatDateTime(item.shownDate);
    final category = cleanCategory(l.category);
    final where = [category, if (l.location.trim().isNotEmpty) l.location.trim()].join(' · ');
    final site = hostOf(l.website);
    final rating = ratingLabel(l.rating, l.totalReviews);
    final review = l.badReview;
    final showReview = item.sourceType == 'review' && (review.text.trim().isNotEmpty || review.date != 'Unknown');
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
          if (verified != null || item.isContacted) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (verified != null)
                  chip(
                    AppIcons.circleCheck,
                    '${_isWhatsApp ? 'On WhatsApp' : 'Email verified'} · $verified',
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
                      Icon(_isWhatsApp ? AppIcons.chat : AppIcons.mail, size: 17, color: t.accentText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: contact,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: t.ink),
                            children: [
                              if (!_isWhatsApp && item.extraEmails > 0)
                                TextSpan(
                                  text: '  +${item.extraEmails} more',
                                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (!_isWhatsApp) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 27),
                      child: Text(
                        [
                          'Found on ${emailSourceLabel(item.emailSource).toLowerCase()}',
                          if (hostOf(item.emailFoundOn) != null) hostOf(item.emailFoundOn)!,
                        ].join(' · '),
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (!_isWhatsApp && l.phone != null && l.phone!.isNotEmpty) detail(AppIcons.phone, l.phone!),
          if (l.address != null && l.address!.isNotEmpty) detail(AppIcons.mapPin, l.address!, lines: 2),
          if (site != null) detail(AppIcons.globe, site),
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
                child: _isWhatsApp
                    ? FilledButton.icon(
                        onPressed: () => _contact(context, () {
                          final message = whatsAppMessageFor(_signal, business: l.business);
                          return actions.whatsapp(whatsAppUrlWithText(_waUrl, message));
                        }, 'Could not open WhatsApp'),
                        icon: const Icon(AppIcons.chat, size: 17),
                        label: const Text('WhatsApp'),
                      )
                    : FilledButton.icon(
                        onPressed: () => _contact(context, () {
                          final mail = outreachEmailFor(_signal, business: l.business);
                          return actions.email(l.email, subject: mail.subject, body: mail.body);
                        }, 'Could not open your email app'),
                        icon: const Icon(AppIcons.mail, size: 17),
                        label: const Text('Email'),
                      ),
              ),
              if (l.phone != null && l.phone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Call',
                  onPressed: () => _contact(context, () => actions.phone(l.phone), 'Could not open the dialer'),
                  icon: const Icon(AppIcons.phone, size: 18),
                ),
              ],
              if (l.website != null && l.website!.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Website',
                  onPressed: () => _act(context, () => actions.website(l.website), 'Could not open the website'),
                  icon: const Icon(AppIcons.globe, size: 18),
                ),
              ],
              if (l.mapsUrl != null && l.mapsUrl!.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Maps',
                  onPressed: () => _act(context, () => actions.maps(l.mapsUrl), 'Could not open Maps'),
                  icon: const Icon(AppIcons.mapPin, size: 18),
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
