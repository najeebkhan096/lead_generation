import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/archive_repository.dart';
import '../services/auth_service.dart';
import '../services/whatsapp_businesses_cache.dart';
import '../services/whatsapp_claim_store.dart';
import '../theme/app_theme.dart';
import '../utils/seeded_shuffle.dart';
import '../widgets/business_row_card.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';
import 'saved_businesses_page.dart' show StateBadge;
import 'whatsapp_validated_archive_page.dart';

const _allCategories = 'All categories';

class _BusinessRow {
  const _BusinessRow({required this.row, required this.category, required this.archiveFileName});

  final Map<String, dynamic> row;
  final String category;
  final String archiveFileName;

  /// Best-effort stable identity for this row — there's no document id here
  /// (these come from an Excel archive, not Firestore), so phone/name/
  /// archive together stand in as the shuffle key.
  String get stableKey =>
      '${row['Phone'] ?? ''}|${row['Business Name'] ?? ''}|$archiveFileName';

  Map<String, dynamic> toCacheJson() => {
        'row': row,
        'category': category,
        'archiveFileName': archiveFileName,
      };

  factory _BusinessRow.fromCacheJson(Map<String, dynamic> json) {
    return _BusinessRow(
      row: Map<String, dynamic>.from(json['row'] as Map? ?? const {}),
      category: (json['category'] as String?) ?? '',
      archiveFileName: (json['archiveFileName'] as String?) ?? '',
    );
  }
}

/// Combines businesses from every WhatsApp-verified archive (see
/// mobile/lib/pages/whatsapp_validated_archive_page.dart, which browses one
/// archive at a time) into a single list, with a category dropdown that
/// filters across all of them at once — every confirmed-WhatsApp business
/// in one category, regardless of which upload batch it came from.
class WhatsAppVerifiedLeadsPage extends StatefulWidget {
  const WhatsAppVerifiedLeadsPage({super.key});

  @override
  State<WhatsAppVerifiedLeadsPage> createState() => _WhatsAppVerifiedLeadsPageState();
}

class _WhatsAppVerifiedLeadsPageState extends State<WhatsAppVerifiedLeadsPage> with WhatsAppClaimsMixin {
  final _archiveRepo = ArchiveRepository();
  final _cache = WhatsAppBusinessesCache();
  final _auth = AuthService();
  List<_BusinessRow> _rows = [];
  bool _loading = true;
  String? _error;
  String _category = _allCategories;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final salesmanId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final approved = await _auth.isCurrentUserApproved();
    if (!approved) {
      await _cache.clear();
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
        _error = 'An error occurred';
      });
      return;
    }

    final cached = salesmanId.isEmpty ? null : await _cache.read(salesmanId: salesmanId);
    if (cached != null && cached.isFresh) {
      if (!mounted) return;
      setState(() {
        _rows = cached.rows.map(_BusinessRow.fromCacheJson).toList();
        _loading = false;
        _error = null;
      });
      return;
    }

    try {
      final archives = await _archiveRepo.listValidatedScans();
      final sheetsPerArchive = await Future.wait(archives.map((a) => _archiveRepo.fetchSheets(a)));

      final rows = <_BusinessRow>[];
      for (var i = 0; i < archives.length; i++) {
        for (final sheet in sheetsPerArchive[i]) {
          for (final row in sheet.rows) {
            final category = (row['Category'] as String?)?.trim();
            rows.add(_BusinessRow(
              row: row,
              category: (category?.isNotEmpty ?? false) ? category! : sheet.name,
              archiveFileName: archives[i].fileName,
            ));
          }
        }
      }
      // Every salesman browses this same shared pool of verified businesses
      // — without this, everyone would see it in the exact same order and
      // tend to message the same top businesses first. Seeding by uid gives
      // each salesman a different, but stable, order instead.
      final ordered = salesmanId.isNotEmpty
          ? seededShuffle(rows, (r) => r.stableKey, salesmanId)
          : rows;

      if (salesmanId.isNotEmpty) {
        try {
          await _cache.write(
            salesmanId: salesmanId,
            rows: [for (final r in ordered) r.toCacheJson()],
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _rows = ordered;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (cached != null) {
        if (!mounted) return;
        setState(() {
          _rows = cached.rows.map(_BusinessRow.fromCacheJson).toList();
          _loading = false;
          _error = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('permission-denied') || raw.contains('PERMISSION_DENIED')) {
      return 'An error occurred';
    }
    return raw.replaceFirst('Exception: ', '');
  }

  List<String> get _categories {
    final present = <String>{};
    for (final r in _rows) {
      if (!claimVisible(r.row)) continue;
      if (r.category.isNotEmpty) present.add(r.category);
    }
    final sorted = present.toList()..sort();
    return [_allCategories, ...sorted];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final available = _rows.where((r) => claimVisible(r.row)).toList();
    final categories = _categories;
    final categoryValue = categories.contains(_category) ? _category : _allCategories;
    var filtered = categoryValue == _allCategories ? available : available.where((r) => r.category == categoryValue).toList();
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((r) {
        final name = (r.row['Business Name'] ?? '').toString().toLowerCase();
        final address = (r.row['Address'] ?? '').toString().toLowerCase();
        final phone = (r.row['Phone'] ?? '').toString().toLowerCase();
        return name.contains(query) || address.contains(query) || phone.contains(query);
      }).toList();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'WhatsApp Verified Leads',
              subtitle: available.isEmpty
                  ? 'Verified businesses from every upload will show up here'
                  : '${filtered.length} of ${available.length} businesses shown',
              trailing: HeaderBadge(icon: AppIcons.shieldCheck, background: t.sageTint, foreground: t.sageDeep),
            ),
            if (available.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SearchField(
                  controller: _searchController,
                  value: _searchQuery,
                  hintText: 'Search businesses...',
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
            if (categories.length > 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: t.neutralTint, borderRadius: BorderRadius.circular(AppTheme.radius)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: categoryValue,
                      isExpanded: true,
                      icon: Icon(AppIcons.chevronDown, size: 18, color: t.subtle),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.ink),
                      items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) {
                        if (v != null) setState(() => _category = v);
                      },
                    ),
                  ),
                ),
              ),
            if (available.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Material(
                  color: t.sageTint,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WhatsAppValidatedArchivePage()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(AppIcons.shieldCheck, size: 18, color: t.sageDeep),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Browse by upload batch',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.sageDeep),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 18, color: t.sageDeep),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ScrollableCenter(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StateBadge(icon: AppIcons.alert, background: t.accentTint, foreground: t.accentText),
                              const SizedBox(height: 20),
                              Text('Could not load businesses', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.danger)),
                              const SizedBox(height: 20),
                              OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? _ScrollableCenter(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StateBadge(icon: AppIcons.shieldCheck, background: t.sageTint, foreground: t.sageDeep),
                                  const SizedBox(height: 20),
                                  Text(
                                    available.isEmpty ? 'No verified businesses yet' : 'No businesses in this category',
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    available.isEmpty
                                        ? 'Validate WhatsApp numbers and upload them from the web app — they show up here.'
                                        : 'Try a different category.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) => _BusinessCard(
                                business: filtered[i],
                                connected: claimIsMine(filtered[i].row),
                                onWhatsAppPressed: () => claimAndOpen(filtered[i].row),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableCenter extends StatelessWidget {
  const _ScrollableCenter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: Padding(padding: const EdgeInsets.all(28), child: child)),
          ),
        );
      },
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.business,
    required this.connected,
    required this.onWhatsAppPressed,
  });

  final _BusinessRow business;
  final bool connected;
  final Future<bool> Function() onWhatsAppPressed;

  @override
  Widget build(BuildContext context) {
    return BusinessRowCard(
      row: business.row,
      badgeLabel: 'WhatsApp Verified',
      categoryLabel: business.category,
      footerLabel: business.archiveFileName,
      connected: connected,
      onWhatsAppPressed: onWhatsAppPressed,
    );
  }
}
