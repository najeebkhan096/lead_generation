import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
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
  final _api = ApiService();
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
      final archives = await _api.listExcelArchives();
      final sheetsPerArchive = await Future.wait(archives.map((a) => _api.getExcelArchiveData(a.id)));

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
              title: 'Excel Sheet Leads',
              subtitle: _rows.isEmpty
                  ? 'Businesses from every archived scan will show up here'
                  : '${filtered.length} of ${_rows.length} businesses shown',
              trailing: HeaderBadge(icon: AppIcons.inbox, background: t.sageTint, foreground: t.sageDeep),
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
    final t = context.tokens;
    final row = business.row;
    final name = (row['Business Name'] ?? '').toString();
    final phone = (row['Phone'] ?? '').toString();
    final rating = (row['Rating'] ?? '').toString();
    final address = (row['Address'] ?? '').toString();
    final hasWhatsApp = (row['Has WhatsApp'] ?? '').toString() == 'Yes';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? 'Unnamed business' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              if (rating.isNotEmpty) ...[
                Icon(AppIcons.star, size: 13, color: t.accentText),
                const SizedBox(width: 3),
                Text(rating, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t.accentText)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  business.category,
                  style: TextStyle(fontSize: 11.5, color: t.faint, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                business.archiveFileName,
                style: TextStyle(fontSize: 10.5, color: t.faint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(address, style: TextStyle(fontSize: 12, color: t.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(AppIcons.phone, size: 12, color: t.subtle),
                const SizedBox(width: 5),
                Text(phone, style: TextStyle(fontSize: 12.5, color: t.subtle, fontWeight: FontWeight.w600)),
                if (hasWhatsApp) ...[
                  const SizedBox(width: 8),
                  Icon(AppIcons.chat, size: 12, color: t.sageDeep),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
