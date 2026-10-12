import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../utils/date_format.dart';
import '../widgets/email_lead_card.dart';

/// Full details for one email lead. Pops `true` if the lead was deleted
/// here, so the list it was opened from knows to refresh.
///
/// Separate from [BusinessDetailsPage] on purpose: that page's WhatsApp
/// status, review, and outreach panels all belong to the other two lead
/// types, and its delete targets the `leads` collection — an email lead
/// needs the `emailLeads` one.
class EmailLeadDetailsPage extends StatefulWidget {
  const EmailLeadDetailsPage({super.key, required this.lead});

  final Lead lead;

  @override
  State<EmailLeadDetailsPage> createState() => _EmailLeadDetailsPageState();
}

class _EmailLeadDetailsPageState extends State<EmailLeadDetailsPage> {
  bool _deleting = false;

  Lead get _lead => widget.lead;

  Future<void> _open(String? url, String failureMessage) async {
    final uri = url == null ? null : Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _delete() async {
    if (_lead.dbId == null || _deleting) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this email lead?'),
        content: Text(
          '"${_lead.business}" will be permanently removed from Firebase. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await context.read<LeadRepository>().deleteEmailLead(_lead.dbId!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = _lead;
    final addedOn = formatDate(lead.savedAt);
    final letter = lead.business.trim().isEmpty ? '?' : lead.business.trim()[0].toUpperCase();
    final warm = lead.business.hashCode.isEven;
    // Everything found on the site, with the chosen address always first
    // even if an older doc has no `emails` list.
    final emails = <String>[
      if (lead.email != null) lead.email!,
      ...lead.emails.where((e) => e != lead.email),
    ];

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Delete email lead',
            onPressed: _deleting ? null : _delete,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.trash),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: warm ? AppTheme.accent100 : AppTheme.sage100,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: warm ? AppTheme.accent700 : AppTheme.sage700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lead.business, style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accent100,
                              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                            ),
                            child: Text(
                              lead.category,
                              style: const TextStyle(
                                color: AppTheme.accent800,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (lead.rating != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                        ),
                        child: Row(
                          children: [
                            const Icon(AppIcons.star, size: 16, color: AppTheme.accent),
                            const SizedBox(width: 4),
                            Text(
                              '${lead.rating}'
                              '${lead.totalReviews != null ? ' (${lead.totalReviews})' : ''}',
                              style: const TextStyle(
                                color: AppTheme.accent800,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                if (emails.isNotEmpty) ...[
                  Text(
                    emails.length == 1 ? 'Email' : 'Emails found',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < emails.length; i++)
                          _EmailRow(
                            email: emails[i],
                            primary: i == 0,
                            sourceLabel: i == 0 ? emailSourceLabel(lead.emailSource) : null,
                            onCompose: () => _open(
                              'mailto:${emails[i]}',
                              'Could not open email app',
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Only web-search results carry the page they came from.
                      if (lead.emailFoundOn != null)
                        _DetailRow(
                          icon: AppIcons.search,
                          label: 'Found on',
                          value: lead.emailFoundOn,
                          onTap: () => _open(lead.emailFoundOn, 'Could not open page'),
                        ),
                      _DetailRow(
                        icon: AppIcons.globe,
                        label: 'Website',
                        value: lead.website,
                        onTap: lead.website == null
                            ? null
                            : () => _open(lead.website, 'Could not open website'),
                      ),
                      _DetailRow(
                        icon: AppIcons.phone,
                        label: 'Phone',
                        value: lead.phone,
                        onTap: lead.phone == null
                            ? null
                            : () => _open('tel:${lead.phone}', 'Could not open dialer'),
                      ),
                      _DetailRow(
                        icon: AppIcons.mapPin,
                        label: 'Address',
                        value: lead.address,
                        onTap: lead.mapsUrl == null
                            ? null
                            : () => _open(lead.mapsUrl, 'No Google Maps link for this business'),
                      ),
                      _DetailRow(icon: AppIcons.mapPinned, label: 'Location', value: lead.location),
                      _DetailRow(icon: AppIcons.calendar, label: 'Date Added', value: addedOn),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({
    required this.email,
    required this.primary,
    required this.onCompose,
    this.sourceLabel,
  });

  final String email;
  final bool primary;
  final String? sourceLabel;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primary ? AppTheme.sage100 : AppTheme.neutral100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              AppIcons.mail,
              size: 15,
              color: primary ? AppTheme.sage700 : AppTheme.subtle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  email,
                  style: TextStyle(
                    fontWeight: primary ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 15,
                    color: AppTheme.ink,
                  ),
                ),
                if (sourceLabel != null)
                  Text(
                    'Found on: $sourceLabel',
                    style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy email',
            onPressed: () => copyToClipboard(context, email, 'Copied $email'),
            icon: const Icon(AppIcons.copy, size: 17),
          ),
          IconButton(
            tooltip: 'Compose email',
            onPressed: onCompose,
            icon: const Icon(AppIcons.externalLink, size: 17),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(color: AppTheme.neutral100, shape: BoxShape.circle),
            child: Icon(icon, size: 15, color: AppTheme.subtle),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              hasValue ? value! : 'Not available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: hasValue && onTap != null ? AppTheme.accent700 : null,
                    fontWeight: hasValue && onTap != null ? FontWeight.w700 : null,
                    fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null || !hasValue) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      onTap: onTap,
      child: content,
    );
  }
}
