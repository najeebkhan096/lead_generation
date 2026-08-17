import 'package:flutter/material.dart';

import '../services/archive_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/business_row_card.dart';
import '../widgets/page_header.dart';
import '../widgets/search_field.dart';
import 'excel_archive_page.dart';
import 'saved_businesses_page.dart' show StateBadge;

const _allCategories = 'All categories';

class _BusinessRow {
  const _BusinessRow({required this.row, required this.category, required this.archiveFileName});

  final Map<String, dynamic> row;
  final String category;
  final String archiveFileName;
}

/// Combines businesses from every archived Excel scan (see
/// mobile/lib/pages/excel_archive_page.dart, which browses one archive at
/// a time) into a single list, with a category dropdown that filters
/// across all of them at once — for "show me every plumber lead across
/// every scan I've ever run," not "what's in this one file."
class ExcelLeadsPage extends StatefulWidget {
  const ExcelLeadsPage({super.key});

  @override
  State<ExcelLeadsPage> createState() => _ExcelLeadsPageState();
}

class _ExcelLeadsPageState extends State<ExcelLeadsPage> {
  final _archiveRepo = ArchiveRepository();
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
    try {
      final archives = await _archiveRepo.listExcelScans();
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
    var filtered = _category == _allCategories ? _rows : _rows.where((r) => r.category == _category).toList();
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
              title: 'Excel Sheet Leads',
              subtitle: _rows.isEmpty
                  ? 'Businesses from every archived scan will show up here'
                  : '${filtered.length} of ${_rows.length} businesses shown',
              trailing: HeaderBadge(icon: AppIcons.inbox, background: t.sageTint, foreground: t.sageDeep),
            ),
            if (_rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SearchField(
                  controller: _searchController,
                  value: _searchQuery,
                  hintText: 'Search businesses...',
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
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
            if (_rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Material(
                  color: t.accentTint,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ExcelArchivePage()),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(AppIcons.inbox, size: 18, color: t.accentText),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Browse by upload batch',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.accentText),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 18, color: t.accentText),
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
                                  StateBadge(icon: AppIcons.inbox, background: t.sageTint, foreground: t.sageDeep),
                                  const SizedBox(height: 20),
                                  Text(
                                    _rows.isEmpty ? 'No archived scans yet' : 'No businesses in this category',
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _rows.isEmpty
                                        ? 'Run an Excel scan from the web app — businesses show up here once it finishes.'
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
      categoryLabel: business.category,
      footerLabel: business.archiveFileName,
    );
  }
}
