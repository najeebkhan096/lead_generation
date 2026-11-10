import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_system/design_system.dart';
import '../../domain/entities/lead.dart';
import '../utils/date_format.dart';

/// Host and path of a URL without the scheme — `https://www.a.com/contact` →
/// `a.com/contact`. Falls back to the text as given.
String shortUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  final path = uri.path == '/' ? '' : uri.path;
  return '$host$path';
}

/// A saved business with **no website** (Website leads): who it is, how to
/// reach it, and where it is on Google Maps. Tapping opens the listing.
class WebsiteLeadCard extends StatelessWidget {
  const WebsiteLeadCard({
    super.key,
    required this.lead,
    required this.onTap,
    this.onDelete,
    this.deleting = false,
  });

  final Lead lead;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    return _SiteLeadCardBase(
      lead: lead,
      onTap: onTap,
      onDelete: onDelete,
      deleting: deleting,
      badge: const _Badge(icon: AppIcons.globe, label: 'No website', tone: AppTone.info),
      rows: [
        if (lead.rating != null)
          _Row(icon: AppIcons.star, text: '${lead.rating}${lead.totalReviews == null ? '' : ' · ${lead.totalReviews} reviews'}'),
        if (_has(lead.phone)) _Row(icon: AppIcons.phone, text: lead.phone!),
        if (_has(lead.address)) _Row(icon: AppIcons.mapPin, text: lead.address!),
        if (_has(lead.mapsUrl)) _Row(icon: AppIcons.externalLink, text: 'Google Maps listing'),
      ],
    );
  }
}

/// A business whose website publishes a **business email** (Email leads): the
/// address(es), the page each came from, and the usual contact details.
class EmailLeadCard extends StatelessWidget {
  const EmailLeadCard({
    super.key,
    required this.lead,
    required this.onTap,
    this.onDelete,
    this.deleting = false,
  });

  final Lead lead;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool deleting;

  /// Every address on file; the headline one alone for a lead without the list.
  List<LeadEmail> get _addresses => lead.emails.isNotEmpty
      ? lead.emails
      : [if (_has(lead.email)) LeadEmail(address: lead.email!, sourceUrl: lead.emailSourceUrl)];

  @override
  Widget build(BuildContext context) {
    final addresses = _addresses;
    final extra = addresses.length - 2;
    return _SiteLeadCardBase(
      lead: lead,
      onTap: onTap,
      onDelete: onDelete,
      deleting: deleting,
      badge: _Badge(
        icon: AppIcons.mail,
        label: lead.emailStatus == 'found' || lead.emailStatus == null ? 'Email found' : lead.emailStatus!.replaceAll('_', ' '),
        tone: AppTone.success,
      ),
      rows: [
        for (final e in addresses.take(2))
          _Row(
            icon: AppIcons.mail,
            text: e.address,
            strong: true,
            trailing: IconButton(
              tooltip: 'Copy email',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              icon: Icon(AppIcons.copy, size: 14, color: AppTheme.textSecondary),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: e.address));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${e.address}')));
                }
              },
            ),
          ),
        if (extra > 0) _Row(icon: AppIcons.plus, text: '$extra more address${extra == 1 ? '' : 'es'}'),
        if (_has(addresses.firstOrNull?.sourceUrl))
          _Row(icon: AppIcons.externalLink, text: 'Found on ${shortUrl(addresses.first.sourceUrl!)}'),
        if (_has(lead.phone)) _Row(icon: AppIcons.phone, text: lead.phone!),
        if (_has(lead.location)) _Row(icon: AppIcons.mapPin, text: lead.location),
      ],
    );
  }
}

bool _has(String? s) => s != null && s.isNotEmpty;

class _SiteLeadCardBase extends StatelessWidget {
  const _SiteLeadCardBase({
    required this.lead,
    required this.onTap,
    required this.onDelete,
    required this.deleting,
    required this.badge,
    required this.rows,
  });

  final Lead lead;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool deleting;
  final Widget badge;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final addedOn = formatDate(lead.savedAt);
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();

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
              if (onDelete != null) AppIconButton(icon: AppIcons.trash, tooltip: 'Delete', size: 30, loading: deleting, onPressed: onDelete),
            ],
          ),
          const SizedBox(height: AppSpace.md + 2),
          ...rows,
          const Spacer(),
          const SizedBox(height: AppSpace.sm + 2),
          Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: badge)),
              if (addedOn != null) Text(addedOn, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text, this.strong = false, this.trailing});

  final IconData icon;
  final String text;
  final bool strong;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: strong ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A card's status badge, in one of the design system's tones.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => AppBadge(label, tone: tone, icon: icon, dense: true);
}
