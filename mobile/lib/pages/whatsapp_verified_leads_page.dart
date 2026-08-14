import 'package:flutter/material.dart';

import '../services/archive_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/business_row_card.dart';
import '../widgets/page_header.dart';
import 'saved_businesses_page.dart' show StateBadge;

const _allCategories = 'All categories';

class _BusinessRow {
  const _BusinessRow({required this.row, required this.category, required this.archiveFileName});

  final Map<String, dynamic> row;
  final String category;
  final String archiveFileName;
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

class _WhatsAppVerifiedLeadsPageState extends State<WhatsAppVerifiedLeadsPage> {
  final _archiveRepo = ArchiveRepository();
  List<_BusinessRow> _rows = [];
  bool _loading = true;
  String? _error;
  String _category = _allCategories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<String> get _categories {
    final present = <String>{};
    for (final r in _rows) {
      if (r.category.isNotEmpty) present.add(r.category);
    }
    final sorted = present.toList()..sort();
    return [_allCategories, ...sorted];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filtered = _category == _allCategories ? _rows : _rows.where((r) => r.category == _category).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'WhatsApp Verified Leads',
              subtitle: _rows.isEmpty
                  ? 'Verified businesses from every upload will show up here'
                  : '${filtered.length} of ${_rows.length} businesses shown',
              trailing: HeaderBadge(icon: AppIcons.shieldCheck, background: t.sageTint, foreground: t.sageDeep),
            ),
            if (_categories.length > 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: t.neutralTint, borderRadius: BorderRadius.circular(AppTheme.radius)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _category,
                      isExpanded: true,
                      icon: Icon(AppIcons.chevronDown, size: 18, color: t.subtle),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: t.ink),
                      items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
                      onChanged: (v) {
                        if (v != null) setState(() => _category = v);
                      },
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
                                    _rows.isEmpty ? 'No verified businesses yet' : 'No businesses in this category',
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _rows.isEmpty
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
                              itemBuilder: (context, i) => _BusinessCard(business: filtered[i]),
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
  const _BusinessCard({required this.business});

  final _BusinessRow business;

  @override
  Widget build(BuildContext context) {
    return BusinessRowCard(
      row: business.row,
      badgeLabel: 'WhatsApp Verified',
      categoryLabel: business.category,
      footerLabel: business.archiveFileName,
    );
  }
}
