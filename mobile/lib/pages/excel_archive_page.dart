import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/excel_archive.dart';
import '../services/archive_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/business_row_card.dart';
import '../widgets/page_header.dart';
import 'excel_leads_page.dart';
import 'saved_businesses_page.dart' show StateBadge;
import 'whatsapp_validated_archive_page.dart';

String _timeAgo(DateTime? when) {
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Browses scans saved as .xlsx workbooks in Firebase Storage — produced by
/// the web app's Excel Scan page, which skips the normal Leads/Firestore
/// collection entirely. View-only here: scanning only happens from the web
/// app (backed by the desktop Launcher), this page just reads what's there.
class ExcelArchivePage extends StatefulWidget {
  const ExcelArchivePage({super.key});

  @override
  State<ExcelArchivePage> createState() => _ExcelArchivePageState();
}

class _ExcelArchivePageState extends State<ExcelArchivePage> {
  final _archiveRepo = ArchiveRepository();
  List<ExcelArchive> _archives = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final archives = await _archiveRepo.listExcelScans();
      if (!mounted) return;
      setState(() {
        _archives = archives;
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Excel Archive',
              subtitle: _archives.isEmpty
                  ? 'Scans saved as Excel files will show up here'
                  : '${_archives.length} archived scan${_archives.length == 1 ? '' : 's'}',
              trailing: HeaderBadge(
                icon: AppIcons.inbox,
                background: t.sageTint,
                foreground: t.sageDeep,
              ),
            ),
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
                            'WhatsApp Verified businesses',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Material(
                color: t.accentTint,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ExcelLeadsPage()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(AppIcons.compass, size: 18, color: t.accentText),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Browse leads by category',
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
                              Text('Could not load archives', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: t.danger)),
                              const SizedBox(height: 20),
                              OutlinedButton.icon(onPressed: _load, icon: const Icon(AppIcons.refresh, size: 18), label: const Text('Retry')),
                            ],
                          ),
                        )
                      : _archives.isEmpty
                          ? _ScrollableCenter(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StateBadge(icon: AppIcons.inbox, background: t.sageTint, foreground: t.sageDeep),
                                  const SizedBox(height: 20),
                                  Text('No Excel archives yet', style: Theme.of(context).textTheme.headlineSmall),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Run an Excel scan from the web app — the file shows up here once it finishes.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                              itemCount: _archives.length,
                              itemBuilder: (context, i) => _ArchiveCard(archive: _archives[i]),
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

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.archive});

  final ExcelArchive archive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _ArchiveViewerPage(archive: archive)),
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: t.sageTint, shape: BoxShape.circle),
                child: Icon(AppIcons.download, size: 18, color: t.sageDeep),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      archive.categories.isNotEmpty ? archive.categories.join(', ') : archive.fileName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${archive.totalLeads} leads · ${archive.countries.join(', ')} · ${_timeAgo(archive.createdAt)}',
                      style: TextStyle(fontSize: 12, color: t.faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchiveViewerPage extends StatefulWidget {
  const _ArchiveViewerPage({required this.archive});

  final ExcelArchive archive;

  @override
  State<_ArchiveViewerPage> createState() => _ArchiveViewerPageState();
}

class _ArchiveViewerPageState extends State<_ArchiveViewerPage> {
  final _archiveRepo = ArchiveRepository();
  List<ExcelArchiveSheet> _sheets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sheets = await _archiveRepo.fetchSheets(widget.archive);
      if (!mounted) return;
      setState(() {
        _sheets = sheets;
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DefaultTabController(
      length: _sheets.isEmpty ? 1 : _sheets.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.archive.fileName, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              icon: const Icon(AppIcons.download),
              onPressed: () => launchUrl(Uri.parse(widget.archive.downloadUrl)),
            ),
          ],
          bottom: _sheets.length > 1
              ? TabBar(isScrollable: true, tabs: [for (final s in _sheets) Tab(text: s.name)])
              : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: t.danger)))
                : _sheets.isEmpty
                    ? Center(child: Text('This workbook has no data.', style: TextStyle(color: t.faint)))
                    : TabBarView(children: [for (final s in _sheets) _SheetList(sheet: s)]),
      ),
    );
  }
}

/// Each row rendered as a card rather than a wide table — a spreadsheet
/// grid doesn't fit a phone screen. See [BusinessRowCard].
class _SheetList extends StatelessWidget {
  const _SheetList({required this.sheet});

  final ExcelArchiveSheet sheet;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (sheet.rows.isEmpty) {
      return Center(child: Text('No rows in this sheet.', style: TextStyle(color: t.faint)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sheet.rows.length,
      itemBuilder: (context, i) => BusinessRowCard(row: sheet.rows[i]),
    );
  }
}
