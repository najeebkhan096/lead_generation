import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/date_labels.dart';
import '../../domain/entities/contacted_lead.dart';
import '../../domain/repositories/lead_repository.dart';

/// Whether [lead] matches a search. Every word of [query] must appear, in any
/// order and ignoring case, in the business, category, location, phone or review.
bool matchesLeadSearch(ContactedLead lead, String query) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = [
    lead.business,
    lead.category ?? '',
    lead.location ?? '',
    lead.phone ?? '',
    lead.reviewText,
  ].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

/// One salesman's contacted leads, newest contact first. The admin can move any
/// of them back to New; the salesman's contact count for today goes down with it
/// when the contact was made today.
class SalesmanContactedLeadsPage extends StatefulWidget {
  const SalesmanContactedLeadsPage({
    super.key,
    required this.userId,
    required this.salesmanName,
  });

  final String userId;
  final String salesmanName;

  @override
  State<SalesmanContactedLeadsPage> createState() =>
      _SalesmanContactedLeadsPageState();
}

class _SalesmanContactedLeadsPageState
    extends State<SalesmanContactedLeadsPage> {
  List<ContactedLead>? _leads;
  bool _loading = true;
  String? _error;
  final Set<String> _busyIds = {};
  final _search = TextEditingController();
  String _query = '';

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final leads = await _repo.getSalesmanContactedLeads(widget.userId);
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _moveBack(ContactedLead lead) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move back to New?'),
        content: Text(
          '${lead.business} will show as a New lead again for ${widget.salesmanName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to New'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyIds.add(lead.id));
    try {
      final refunded = await _repo.moveContactedLeadBack(
        widget.userId,
        lead.id,
      );
      if (!mounted) return;
      setState(() {
        _leads = _leads?.where((l) => l.id != lead.id).toList();
        _busyIds.remove(lead.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refunded
                ? '${lead.business} is New again. Today\'s count went down by one.'
                : '${lead.business} is New again.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(lead.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.salesmanName} · contacted'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(AppIcons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _leads == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _leads == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.danger),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(AppIcons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final all = _leads ?? const [];
    final leads = all.where((l) => matchesLeadSearch(l, _query)).toList();
    final searching = _query.trim().isNotEmpty;
    final String summary;
    if (all.isEmpty) {
      summary = '${widget.salesmanName} has not contacted any leads yet.';
    } else if (searching) {
      summary = '${leads.length} of ${all.length} match "${_query.trim()}"';
    } else {
      summary =
          '${all.length} contacted ${all.length == 1 ? 'lead' : 'leads'} · newest first';
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        if (all.isNotEmpty) ...[
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search business, category, place, phone or review',
              prefixIcon: const Icon(AppIcons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(AppIcons.close, size: 16),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          summary,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppTheme.faint,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (searching && leads.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No contacted leads match that search.',
                style: TextStyle(color: AppTheme.faint),
              ),
            ),
          ),
        for (final lead in leads)
          _LeadCard(
            lead: lead,
            busy: _busyIds.contains(lead.id),
            onMoveBack: () => _moveBack(lead),
          ),
      ],
    );
  }
}

/// The business name. When the lead has a Google Maps listing, the name opens it.
class _BusinessName extends StatelessWidget {
  const _BusinessName({required this.lead});

  final ContactedLead lead;

  @override
  Widget build(BuildContext context) {
    final url = lead.mapsUrl;
    final name = Text(
      lead.business,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: url == null || url.isEmpty ? null : AppTheme.accent700,
        decoration: url == null || url.isEmpty
            ? null
            : TextDecoration.underline,
      ),
    );
    if (url == null || url.isEmpty) return name;
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: name),
          const SizedBox(width: 6),
          const Icon(AppIcons.mapPin, size: 14, color: AppTheme.accent700),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.busy,
    required this.onMoveBack,
  });

  final ContactedLead lead;
  final bool busy;
  final VoidCallback onMoveBack;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (lead.category != null && lead.category!.isNotEmpty) lead.category!,
      if (lead.location != null && lead.location!.isNotEmpty) lead.location!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BusinessName(lead: lead),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.faint,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed: onMoveBack,
                      icon: const Icon(AppIcons.refresh, size: 16),
                      label: const Text('Move to New'),
                    ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (lead.phone != null && lead.phone!.isNotEmpty)
                Text(
                  lead.phone!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (lead.contactedAt != null)
                Text(
                  'Contacted ${dateTimeLabel(lead.contactedAt!)}',
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.faint),
                ),
              if (lead.rating != null)
                Text(
                  lead.totalReviews == null
                      ? '★ ${lead.rating!.toStringAsFixed(1)}'
                      : '★ ${lead.rating!.toStringAsFixed(1)} · ${lead.totalReviews} reviews',
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.faint),
                ),
            ],
          ),
          if (lead.reviewText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${lead.reviewText.trim()}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}
