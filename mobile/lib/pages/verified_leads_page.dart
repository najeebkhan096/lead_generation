import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/open_links.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';

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

const _allCategories = 'All';

class _Row {
  const _Row(this.lead, this.sourceType);

  final Lead lead;

  /// `review` (1-star) or `website` (no website) — which signal the lead
  /// was found by. Absent on documents written before the field existed.
  final String? sourceType;
}

/// A verified lead list — the output of one of the two validators.
///
/// Reads the dedicated collection straight from Firestore (the same way
/// the Leads tab does), so a lead the web console validates shows up here
/// live, without any archive step.
class VerifiedLeadsPage extends StatefulWidget {
  const VerifiedLeadsPage({super.key, required this.kind});

  final VerifiedKind kind;

  @override
  State<VerifiedLeadsPage> createState() => _VerifiedLeadsPageState();
}

class _VerifiedLeadsPageState extends State<VerifiedLeadsPage> {
  final _search = TextEditingController();
  String _query = '';
  String _category = _allCategories;
  String? _source; // null = all, 'review', 'website'
  late final Stream<List<_Row>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collection(widget.kind.collection)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => [
              for (final doc in snap.docs) _Row(Lead.fromDoc(doc), doc.data()['sourceType'] as String?),
            ]);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _isWhatsApp => widget.kind == VerifiedKind.whatsapp;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<_Row>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Message(
                icon: AppIcons.alert,
                title: 'Could not load ${widget.kind.title} leads',
                body: snapshot.error.toString(),
              );
            }

            final all = snapshot.data ?? const <_Row>[];
            final categories = <String>{
              for (final r in all) if (r.lead.category.trim().isNotEmpty) r.lead.category.trim(),
            }.toList()
              ..sort();
            final category = categories.contains(_category) ? _category : _allCategories;

            final q = _query.trim().toLowerCase();
            final rows = all.where((r) {
              if (category != _allCategories && r.lead.category != category) return false;
              if (_source != null && r.sourceType != _source) return false;
              if (q.isEmpty) return true;
              final l = r.lead;
              return l.business.toLowerCase().contains(q) ||
                  l.location.toLowerCase().contains(q) ||
                  (l.phone ?? '').toLowerCase().contains(q) ||
                  (l.email ?? '').toLowerCase().contains(q);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: '${widget.kind.title} leads',
                  subtitle: all.isEmpty
                      ? widget.kind.emptyHint
                      : '${rows.length} ${rows.length == 1 ? 'business' : 'businesses'} verified',
                  trailing: HeaderBadge(
                    icon: _isWhatsApp ? AppIcons.chat : AppIcons.mail,
                    background: t.accentTint,
                    foreground: t.accentDeep,
                  ),
                ),
                if (all.isEmpty)
                  Expanded(
                    child: _Message(
                      icon: _isWhatsApp ? AppIcons.chat : AppIcons.mail,
                      title: 'No ${widget.kind.title} leads yet',
                      body: 'Validate leads from the web console and they appear here.',
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        SearchField(
                          controller: _search,
                          value: _query,
                          hintText: 'Search ${widget.kind.title.toLowerCase()} leads...',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _Chip(
                                label: 'All signals',
                                selected: _source == null,
                                onTap: () => setState(() => _source = null),
                              ),
                              _Chip(
                                label: '1-star',
                                selected: _source == 'review',
                                onTap: () => setState(() => _source = 'review'),
                              ),
                              _Chip(
                                label: 'No website',
                                selected: _source == 'website',
                                onTap: () => setState(() => _source = 'website'),
                              ),
                            ],
                          ),
                        ),
                        if (categories.length > 1) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _Chip(
                                  label: _allCategories,
                                  selected: category == _allCategories,
                                  onTap: () => setState(() => _category = _allCategories),
                                ),
                                for (final c in categories)
                                  _Chip(
                                    label: c,
                                    selected: category == c,
                                    onTap: () => setState(() => _category = c),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const _Message(
                            icon: AppIcons.searchX,
                            title: 'No matches',
                            body: 'Try a different name, number or filter.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                            itemCount: rows.length,
                            itemBuilder: (context, i) => _VerifiedCard(row: rows[i], kind: widget.kind),
                          ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: t.accentTint,
        showCheckmark: false,
      ),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: t.accentTint, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: t.accentDeep),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(body, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
