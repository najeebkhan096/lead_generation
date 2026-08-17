import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/repositories/lead_repository.dart';
import 'excel_archive_leads_page.dart';

String _timeAgo(DateTime? when) {
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Browses every scan saved as an .xlsx via the Excel Scan page (see
/// [ExcelScanPage]) — these never touched Firestore, so this page (backed
/// by Firebase Storage + a small metadata record per archive) is the only
/// place to find them again. Available on web and mobile since both talk
/// to the same backend.
class ExcelArchivePage extends StatefulWidget {
  const ExcelArchivePage({super.key});

  @override
  State<ExcelArchivePage> createState() => _ExcelArchivePageState();
}

class _ExcelArchivePageState extends State<ExcelArchivePage> {
  List<ExcelArchive> _archives = [];
  bool _loading = true;
  String? _error;
  String? _resumingId;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final archives = await _repo.listExcelArchives();
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

  Future<void> _delete(ExcelArchive archive) async {
    try {
      await _repo.deleteExcelArchive(archive.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// Picks a stranded `status: 'partial'` archive back up — only the
  /// states/countries that never finished get re-scraped, the rest is
  /// recovered from the archive's existing workbook. Routes to whichever
  /// live dashboard the backend says actually picked it up.
  Future<void> _resume(ExcelArchive archive) async {
    setState(() => _resumingId = archive.id);
    try {
      final engine = await _repo.resumeExcelArchive(archive.id);
      if (!mounted) return;
      context.push(engine == 'multi-country' ? '/multi-scan' : '/scan-progress');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _resumingId = null);
    }
  }

  void _open(ExcelArchive archive) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ExcelArchiveViewerPage(archive: archive)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel Archive'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.refresh), onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                        ),
                      )
                    : _archives.isEmpty
                        ? const _EmptyArchiveState()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                            children: [
                              for (final archive in _archives)
                                _ArchiveCard(
                                  archive: archive,
                                  onTap: () => _open(archive),
                                  onDelete: () => _delete(archive),
                                  onResume: () => _resume(archive),
                                  resuming: _resumingId == archive.id,
                                ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}

class _EmptyArchiveState extends StatelessWidget {
  const _EmptyArchiveState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppTheme.accent100, shape: BoxShape.circle),
              child: const Icon(AppIcons.inbox, size: 30, color: AppTheme.accent700),
            ),
            const SizedBox(height: 16),
            Text('No Excel archives yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Run a scan from the Excel Scan page — the workbook shows up here once it finishes.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.archive,
    required this.onTap,
    required this.onDelete,
    required this.onResume,
    required this.resuming,
  });

  final ExcelArchive archive;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onResume;
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: AppTheme.sage100, shape: BoxShape.circle),
                child: const Icon(AppIcons.download, size: 18, color: AppTheme.sage700),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            archive.categories.isNotEmpty ? archive.categories.join(', ') : archive.fileName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (archive.status == 'partial') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration:
                                BoxDecoration(color: AppTheme.accent100, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                            child: const Text(
                              'In progress',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.accent700),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${archive.totalLeads} leads · ${archive.countries.join(', ')} · ${_timeAgo(archive.createdAt)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (archive.resumable) ...[
                resuming
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : OutlinedButton.icon(
                        onPressed: onResume,
                        icon: const Icon(AppIcons.refresh, size: 15),
                        label: const Text('Resume'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accent700,
                          side: const BorderSide(color: AppTheme.accent300),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'View as leads',
                icon: const Icon(AppIcons.leads, size: 18, color: AppTheme.faint),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ExcelArchiveLeadsPage(archive: archive)),
                ),
              ),
              if (archive.totalLeads > 0)
                IconButton(
                  tooltip: 'Validate WhatsApp',
                  icon: const Icon(AppIcons.chat, size: 18, color: AppTheme.sage700),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ExcelArchiveLeadsPage(archive: archive, autoValidate: true),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Download .xlsx',
                icon: const Icon(AppIcons.download, size: 18, color: AppTheme.faint),
                onPressed: () => launchUrl(Uri.parse(archive.downloadUrl)),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(AppIcons.trash, size: 18, color: AppTheme.faint),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Table view of one archived workbook — a tab per worksheet (category),
/// since a multi-category/country scan produces one sheet each.
class _ExcelArchiveViewerPage extends StatefulWidget {
  const _ExcelArchiveViewerPage({required this.archive});

  final ExcelArchive archive;

  @override
  State<_ExcelArchiveViewerPage> createState() => _ExcelArchiveViewerPageState();
}

class _ExcelArchiveViewerPageState extends State<_ExcelArchiveViewerPage> {
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
      final sheets = await context.read<LeadRepository>().getExcelArchiveData(widget.archive.id);
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.archive.fileName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.archive.fileName)),
        body: Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger))),
      );
    }

    return DefaultTabController(
      length: _sheets.isEmpty ? 1 : _sheets.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.archive.fileName, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ExcelArchiveLeadsPage(archive: widget.archive)),
              ),
              icon: const Icon(AppIcons.leads, size: 18),
              label: const Text('View as Leads'),
            ),
            IconButton(
              tooltip: 'Download .xlsx',
              icon: const Icon(AppIcons.download),
              onPressed: () => launchUrl(Uri.parse(widget.archive.downloadUrl)),
            ),
            const SizedBox(width: 8),
          ],
          bottom: _sheets.length > 1
              ? TabBar(
                  isScrollable: true,
                  tabs: [for (final s in _sheets) Tab(text: s.name)],
                )
              : null,
        ),
        body: _sheets.isEmpty
            ? const Center(child: Text('This workbook has no data.', style: TextStyle(color: AppTheme.faint)))
            : TabBarView(
                children: [for (final s in _sheets) _SheetTable(sheet: s)],
              ),
      ),
    );
  }
}

class _SheetTable extends StatelessWidget {
  const _SheetTable({required this.sheet});

  final ExcelArchiveSheet sheet;

  @override
  Widget build(BuildContext context) {
    if (sheet.rows.isEmpty) {
      return const Center(child: Text('No rows in this sheet.', style: TextStyle(color: AppTheme.faint)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppTheme.neutral100),
          columns: [for (final h in sheet.headers) DataColumn(label: Text(h))],
          rows: [
            for (final row in sheet.rows)
              DataRow(
                cells: [
                  for (final h in sheet.headers) DataCell(Text(row[h]?.toString() ?? '')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
