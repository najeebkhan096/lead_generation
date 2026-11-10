import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/lead.dart';
import '../design_system/design_system.dart';
import '../utils/date_format.dart';

/// Which saved list a table shows — decides its columns.
enum LeadTableKind { review, website, email, whatsapp }

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// Every address on file for [lead]; the headline one alone for a lead without a list.
List<LeadEmail> leadEmails(Lead lead) =>
    lead.emails.isNotEmpty ? lead.emails : [if (_has(lead.email)) LeadEmail(address: lead.email!, sourceUrl: lead.emailSourceUrl)];

Future<void> copyText(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// What a row's primary action is (the card's tap), for the actions column.
class LeadRowAction {
  const LeadRowAction({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;
}

/// The columns of a lead table.
///
/// [onOpen] is the row's primary action (the same one a card tap runs);
/// [onDelete] is `null` for a lead that cannot be deleted.
List<AppColumn<Lead>> leadTableColumns(
  LeadTableKind kind, {
  required void Function(Lead lead) onOpen,
  required void Function(Lead lead)? Function(Lead lead) onDelete,
  required String? deletingId,
  required LeadRowAction action,
}) {
  final business = AppColumn<Lead>(
    label: 'Business',
    flex: 3,
    minWidth: 210,
    sortable: true,
    cell: (context, lead) => _BusinessCell(lead: lead),
  );
  final category = AppColumn<Lead>(
    label: 'Category',
    flex: 2,
    minWidth: 140,
    sortable: true,
    priority: 2,
    cell: (context, lead) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lead.category.isEmpty ? '—' : lead.category, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (lead.location.isNotEmpty)
          Text(lead.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
  final phone = AppColumn<Lead>(
    label: 'Phone',
    width: 200,
    cell: (context, lead) => !_has(lead.phone)
        ? Text('—', style: TextStyle(color: AppTheme.textMuted))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(lead.phone!, maxLines: 1, overflow: TextOverflow.ellipsis)),
              _CopyButton(tooltip: 'Copy phone', onPressed: () => copyText(context, lead.phone!, 'Copied ${lead.phone}')),
            ],
          ),
  );
  final rating = AppColumn<Lead>(
    label: 'Rating',
    width: 104,
    sortable: true,
    cell: (context, lead) => lead.rating == null
        ? Text('—', style: TextStyle(color: AppTheme.textMuted))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.star, size: 13, color: AppTheme.warning),
              const SizedBox(width: 4),
              Flexible(child: Text('${lead.rating}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (lead.totalReviews != null) ...[
                const SizedBox(width: 4),
                Flexible(child: Text('(${groupedNumber(lead.totalReviews!)})', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ],
          ),
  );
  final added = AppColumn<Lead>(
    label: 'Added',
    width: 118,
    sortable: true,
    priority: 3,
    cell: (context, lead) => Text(formatDate(lead.savedAt) ?? '—', style: Theme.of(context).textTheme.bodyMedium),
  );
  final actions = AppColumn<Lead>(
    label: '',
    width: 88,
    alignment: Alignment.centerRight,
    cell: (context, lead) {
      final remove = onDelete(lead);
      final deleting = deletingId != null && deletingId == lead.dbId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(icon: action.icon, tooltip: action.tooltip, size: 32, onPressed: () => onOpen(lead)),
          if (remove != null)
            AppIconButton(icon: AppIcons.trash, tooltip: 'Delete', size: 32, loading: deleting, color: AppTheme.error, onPressed: () => remove(lead)),
        ],
      );
    },
  );

  switch (kind) {
    case LeadTableKind.review:
      return [
        business,
        category,
        phone,
        rating,
        AppColumn<Lead>(
          label: 'Latest 1★ review',
          flex: 3,
          minWidth: 200,
          priority: 1,
          cell: (context, lead) => _has(lead.badReview.text)
              ? Text(lead.badReview.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)
              : Text('—', style: TextStyle(color: AppTheme.textMuted)),
        ),
        AppColumn<Lead>(label: 'WhatsApp', width: 148, cell: (context, lead) => _WhatsAppBadge(lead: lead)),
        added,
        actions,
      ];
    case LeadTableKind.whatsapp:
      return [
        business,
        category,
        phone,
        rating,
        AppColumn<Lead>(label: 'Status', width: 120, cell: (context, lead) => const AppBadge('Verified', tone: AppTone.success, icon: AppIcons.shieldCheck, dense: true)),
        added,
        actions,
      ];
    case LeadTableKind.website:
      return [
        business,
        category,
        phone,
        rating,
        AppColumn<Lead>(label: 'Website', width: 120, cell: (context, lead) => const AppBadge('No website', tone: AppTone.info, icon: AppIcons.globe, dense: true)),
        added,
        actions,
      ];
    case LeadTableKind.email:
      return [
        business,
        AppColumn<Lead>(
          label: 'Email',
          flex: 3,
          minWidth: 230,
          cell: (context, lead) => _EmailsCell(lead: lead),
        ),
        category,
        phone,
        added,
        actions,
      ];
  }
}

/// The column's sort order, by its label.
int Function(Lead a, Lead b)? leadComparator(String label) {
  int text(String? a, String? b) => (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());
  return switch (label) {
    'Business' => (a, b) => text(a.business, b.business),
    'Category' => (a, b) => text(a.category, b.category),
    'Rating' => (a, b) => (a.rating ?? -1).compareTo(b.rating ?? -1),
    'Added' => (a, b) => (a.savedAt ?? DateTime(0)).compareTo(b.savedAt ?? DateTime(0)),
    _ => null,
  };
}

class _BusinessCell extends StatelessWidget {
  const _BusinessCell({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    final sub = _has(lead.address) ? lead.address! : lead.location;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppTheme.primary100, borderRadius: BorderRadius.circular(AppTheme.radius)),
          child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary700, fontSize: 13)),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lead.business, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _WhatsAppBadge extends StatelessWidget {
  const _WhatsAppBadge({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    if (lead.hasWhatsApp) return const AppBadge('On WhatsApp', tone: AppTone.success, icon: AppIcons.shieldCheck, dense: true);
    if (lead.whatsAppCheckedAt != null) return const AppBadge('No WhatsApp', tone: AppTone.neutral, dense: true);
    return const AppBadge('Not checked', tone: AppTone.warning, dot: true, dense: true);
  }
}

class _EmailsCell extends StatelessWidget {
  const _EmailsCell({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final emails = leadEmails(lead);
    if (emails.isEmpty) return const AppBadge('Not found', tone: AppTone.neutral, dense: true);
    final extra = emails.length - 1;
    return Row(
      children: [
        Flexible(child: Text(emails.first.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
        _CopyButton(tooltip: 'Copy email', onPressed: () => copyText(context, emails.first.address, 'Copied ${emails.first.address}')),
        if (extra > 0)
          Tooltip(
            message: emails.skip(1).map((e) => e.address).join('\n'),
            child: AppBadge('+$extra', tone: AppTone.primary, dense: true),
          ),
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(AppIcons.copy, size: 13, color: AppTheme.textMuted),
      style: IconButton.styleFrom(minimumSize: const Size(26, 26), fixedSize: const Size(26, 26), padding: EdgeInsets.zero),
    );
  }
}

// ── CSV ──────────────────────────────────────────────────────────────────

String _csvCell(Object? value) {
  final s = (value ?? '').toString();
  return (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// The leads as a UTF-8 CSV (with a BOM so Excel reads accents correctly),
/// every business and email field included.
Uint8List leadsToCsv(List<Lead> leads) {
  const header = [
    'Business', 'Category', 'Location', 'Address', 'Phone', 'Emails', 'Email source', 'Website', 'Rating',
    'Reviews', 'On WhatsApp', 'Google Maps URL', 'Latest 1-star review', 'Review date', 'Added',
  ];
  final rows = <List<Object?>>[
    for (final l in leads)
      [
        l.business,
        l.category,
        l.location,
        l.address,
        l.phone,
        leadEmails(l).map((e) => e.address).join('; '),
        leadEmails(l).map((e) => e.sourceUrl ?? '').where((s) => s.isNotEmpty).join('; '),
        l.website,
        l.rating,
        l.totalReviews,
        l.hasWhatsApp ? 'Yes' : (l.whatsAppCheckedAt != null ? 'No' : 'Not checked'),
        l.mapsUrl,
        l.badReview.text,
        l.badReview.date == 'Unknown' ? '' : l.badReview.date,
        l.savedAt?.toIso8601String(),
      ],
  ];
  final buffer = StringBuffer('﻿')
    ..writeln(header.map(_csvCell).join(','))
    ..writeAll(rows.map((r) => r.map(_csvCell).join(',')), '\n');
  return Uint8List.fromList(utf8.encode(buffer.toString()));
}
