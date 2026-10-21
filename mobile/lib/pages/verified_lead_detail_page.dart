import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/lead_labels.dart';
import '../widgets/verified_lead_card.dart';

/// Marks a contacted lead a deal done (`done: true`), or reopens it to
/// Contacted (`false`). Returns false when it was refused — the caller says why.
typedef DealDoneAction = Future<bool> Function(bool done);

/// Runs a server write for a lead. Returns false, and says why, when it is
/// refused: the server's own words for a refusal, otherwise a connection hint.
Future<bool> runLeadWrite(BuildContext context, Future<void> Function() write) async {
  const refused = {'resource-exhausted', 'failed-precondition', 'permission-denied'};
  String failure = 'Could not update the lead. Check your connection.';
  try {
    await write();
    return true;
  } on FirebaseFunctionsException catch (e) {
    if (refused.contains(e.code) && e.message != null) failure = e.message!;
  } catch (_) {
    // Keep the connection hint.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failure)));
  }
  return false;
}

/// One WhatsApp lead in full: the contact, the 1-star review, and where it
/// stands. A lead this salesman has contacted can be marked a deal done here;
/// a done deal can be reopened.
class VerifiedLeadDetailPage extends StatefulWidget {
  const VerifiedLeadDetailPage({
    super.key,
    required this.item,
    required this.onDealDone,
    this.onWhatsApp,
    this.actions = const LeadActions(),
  });

  final VerifiedLead item;

  /// Sets the deal status on the server (see [DealDoneAction]).
  final DealDoneAction onDealDone;

  /// Opens WhatsApp for the lead, and returns whether it did. A New lead is
  /// marked Contacted by this first. Without it, WhatsApp opens directly.
  final Future<bool> Function()? onWhatsApp;

  final LeadActions actions;

  @override
  State<VerifiedLeadDetailPage> createState() => _VerifiedLeadDetailPageState();
}

class _VerifiedLeadDetailPageState extends State<VerifiedLeadDetailPage> {
  /// Follows the server's answer, which the list shows through its listener.
  late bool _contacted = widget.item.isContacted;
  late bool _dealDone = widget.item.isDealDone;
  bool _busy = false;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _whatsApp() async {
    final lead = widget.item.lead;
    final owner = widget.onWhatsApp;
    final opened = owner != null ? await owner() : await widget.actions.whatsapp(lead.whatsAppUrl);
    if (!mounted) return;
    if (!opened) {
      _say('Could not open WhatsApp');
      return;
    }
    setState(() => _contacted = true);
  }

  Future<void> _setDealDone(bool done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onDealDone(done);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _dealDone = done;
    });
    if (ok) _say(done ? 'Moved to Deals' : 'Moved back to Contacted');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final lead = widget.item.lead;
    final name = lead.business.trim();
    final category = cleanCategory(lead.category);
    final where = [category, if (lead.location.trim().isNotEmpty) lead.location.trim()].join(' · ');
    final rating = ratingLabel(lead.rating, lead.totalReviews);
    final phone = lead.phone?.trim() ?? '';
    final address = lead.address?.trim() ?? '';
    final mapsUrl = lead.mapsUrl?.trim() ?? '';
    final review = lead.badReview;
    final showReview = review.text.trim().isNotEmpty || review.date != 'Unknown';
    final status = _dealDone
        ? LeadStatus.dealDone
        : _contacted
            ? LeadStatus.contacted
            : LeadStatus.lead;
    final verified = formatDateTime(widget.item.shownDate);
    final contacted = formatDateTime(widget.item.contactedAt);
    final dealAt = formatDateTime(widget.item.dealDoneAt);

    Widget field(IconData icon, String label, String value, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: t.subtle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 11.5, color: t.faint, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(value, style: text.bodyLarge),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Lead details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(name.isEmpty ? 'Unnamed business' : name, style: text.headlineSmall),
          if (where.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(where, style: TextStyle(color: t.faint, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                icon: AppIcons.handshake,
                label: [
                  status.label,
                  if (_dealDone && dealAt != null) dealAt else if (!_dealDone && contacted != null) contacted,
                ].join(' · '),
                background: _dealDone ? t.sageTint : t.accentTint,
                foreground: _dealDone ? t.sageText : t.accentTextStrong,
              ),
              if (verified != null)
                _Chip(
                  icon: AppIcons.circleCheck,
                  label: 'On WhatsApp · $verified',
                  background: t.sageTint,
                  foreground: t.sageText,
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (phone.isNotEmpty) field(AppIcons.phone, 'Phone', phone, onTap: () => openPhone(phone)),
          if (address.isNotEmpty) field(AppIcons.mapPin, 'Address', address),
          if (rating != null) field(AppIcons.star, 'Rating', rating),
          if (showReview) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                    const SizedBox(height: 6),
                    Text('“${review.text.trim()}”', style: text.bodyMedium?.copyWith(color: t.ink)),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: phone.isEmpty ? null : _whatsApp,
            icon: const Icon(AppIcons.chat, size: 18),
            label: const Text('WhatsApp'),
          ),
          if (mapsUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                if (!await widget.actions.maps(mapsUrl)) _say('Could not open Maps');
              },
              icon: const Icon(AppIcons.mapPin, size: 18),
              label: const Text('Map'),
            ),
          ],
          const SizedBox(height: 24),
          if (_contacted && !_dealDone)
            FilledButton.icon(
              onPressed: _busy ? null : () => _setDealDone(true),
              style: FilledButton.styleFrom(backgroundColor: t.sage, foregroundColor: t.onFill),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.check, size: 18),
              label: const Text('Mark as deal done'),
            ),
          if (_dealDone)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _setDealDone(false),
              icon: const Icon(AppIcons.refresh, size: 16),
              label: const Text('Reopen to Contacted'),
            ),
          if (!_contacted)
            Text(
              'Message this lead on WhatsApp first. Once it is Contacted you can mark it a deal done.',
              style: TextStyle(color: t.faint, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.background, required this.foreground});

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
