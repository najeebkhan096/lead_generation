import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../utils/date_format.dart';

/// Full details for a single saved business. Pops `true` if the lead's
/// WhatsApp status was manually changed here, so the list it was opened
/// from knows to refresh.
class BusinessDetailsPage extends StatefulWidget {
  const BusinessDetailsPage({super.key, required this.lead});

  final Lead lead;

  @override
  State<BusinessDetailsPage> createState() => _BusinessDetailsPageState();
}

class _BusinessDetailsPageState extends State<BusinessDetailsPage> {
  late Lead _lead;
  bool _updating = false;
  bool _changed = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _lead = widget.lead;
  }

  String? get _whatsAppUrl {
    if (_lead.waLink != null && _lead.waLink!.isNotEmpty) return _lead.waLink;
    final digits = (_lead.phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return 'https://wa.me/$digits';
  }

  Future<void> _open(BuildContext context, String? url, String failureMessage) async {
    final uri = url == null ? null : Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _markWhatsApp(bool hasWhatsApp) async {
    if (_lead.dbId == null || _updating) return;
    setState(() => _updating = true);
    try {
      await context.read<LeadRepository>().markLeadWhatsAppStatus(_lead.dbId!, hasWhatsApp);
      if (!mounted) return;
      setState(() {
        _lead = _lead.copyWith(hasWhatsApp: hasWhatsApp, whatsAppCheckedAt: DateTime.now());
        _changed = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _deleteLead() async {
    if (_lead.dbId == null || _deleting) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this business?'),
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
      await context.read<LeadRepository>().deleteLead(_lead.dbId!);
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Delete business',
            onPressed: _deleting ? null : _deleteLead,
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
                      _DetailRow(icon: AppIcons.tag, label: 'Category', value: lead.category),
                      _DetailRow(
                        icon: AppIcons.phone,
                        label: 'Phone',
                        value: lead.phone,
                        onTap: lead.phone == null
                            ? null
                            : () => _open(context, 'tel:${lead.phone}', 'Could not open dialer'),
                      ),
                      _DetailRow(
                        icon: AppIcons.globe,
                        label: 'Website',
                        value: lead.website,
                        onTap: lead.website == null
                            ? null
                            : () => _open(context, lead.website, 'Could not open website'),
                      ),
                      _DetailRow(
                        icon: AppIcons.mail,
                        label: 'Email',
                        value: lead.email,
                        onTap: lead.email == null
                            ? null
                            : () => _open(context, 'mailto:${lead.email}', 'Could not open email app'),
                      ),
                      _DetailRow(
                        icon: AppIcons.mapPin,
                        label: 'Address',
                        value: lead.address,
                        onTap: lead.mapsUrl == null
                            ? null
                            : () => _open(context, lead.mapsUrl, 'No Google Maps link for this business'),
                      ),
                      _DetailRow(icon: AppIcons.mapPinned, label: 'Location', value: lead.location),
                      _DetailRow(
                        icon: AppIcons.chat,
                        label: 'WhatsApp',
                        value: _whatsAppUrl,
                        onTap: _whatsAppUrl == null
                            ? null
                            : () => _open(context, _whatsAppUrl, 'No phone number for WhatsApp'),
                      ),
                      _DetailRow(icon: AppIcons.calendar, label: 'Date Added', value: addedOn),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _WhatsAppStatusCard(
                  lead: lead,
                  updating: _updating,
                  onMark: _markWhatsApp,
                ),
                if (lead.badReview.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Flagged review', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.accent100,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(AppIcons.thumbsDown, size: 14, color: AppTheme.accent700),
                            const SizedBox(width: 8),
                            Text(
                              '${lead.badReview.stars}★ · ${lead.badReview.date}'
                              '${lead.badReview.reviewer != null ? ' · ${lead.badReview.reviewer}' : ''}',
                              style: const TextStyle(
                                color: AppTheme.accent700,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '“${lead.badReview.text}”',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppTheme.ink,
                                fontStyle: FontStyle.italic,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _WhatsAppStatusCard extends StatelessWidget {
  const _WhatsAppStatusCard({
    required this.lead,
    required this.updating,
    required this.onMark,
  });

  final Lead lead;
  final bool updating;
  final ValueChanged<bool> onMark;

  @override
  Widget build(BuildContext context) {
    final checked = lead.whatsAppCheckedAt != null;
    final label = !checked
        ? 'Not checked yet'
        : lead.hasWhatsApp
            ? 'WhatsApp verified'
            : 'Not on WhatsApp';
    final color = !checked
        ? AppTheme.subtle
        : lead.hasWhatsApp
            ? AppTheme.sage700
            : AppTheme.accent700;
    final background = !checked
        ? AppTheme.neutral100
        : lead.hasWhatsApp
            ? AppTheme.sage100
            : AppTheme.accent100;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('WhatsApp status', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Checked it yourself on your phone? Record the result here.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: updating ? null : () => onMark(true),
                  icon: const Icon(AppIcons.checkCircle, size: 17),
                  label: const Text('Mark validated'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.sage700,
                    side: const BorderSide(color: AppTheme.sage500),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: updating ? null : () => onMark(false),
                  icon: const Icon(AppIcons.close, size: 17),
                  label: const Text('Not on WhatsApp'),
                ),
              ),
            ],
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
    return InkWell(borderRadius: BorderRadius.circular(AppTheme.radius), onTap: onTap, child: content);
  }
}
