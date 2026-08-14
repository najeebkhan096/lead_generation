import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/excel_archive.dart';
import '../services/api_service.dart';
import '../services/archive_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/business_row_card.dart';
import '../widgets/page_header.dart';
import 'saved_businesses_page.dart' show StateBadge;
import 'whatsapp_verified_leads_page.dart';

String _timeAgo(DateTime? when) {
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Browses businesses that passed real WhatsApp Web validation from the
/// web app's Excel Archive "Upload Verified" action — a separate Firebase
/// collection from the source Excel scans, holding only confirmed
/// WhatsApp-registered numbers. View-only, same as the Excel Archive tab:
/// validation only runs from the web app.
class WhatsAppValidatedArchivePage extends StatefulWidget {
  const WhatsAppValidatedArchivePage({super.key});

  @override
  State<WhatsAppValidatedArchivePage> createState() => _WhatsAppValidatedArchivePageState();
}

class _WhatsAppValidatedArchivePageState extends State<WhatsAppValidatedArchivePage> {
  final _api = ApiService();
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
      final archives = await _archiveRepo.listValidatedScans();
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
      await _api.deleteValidatedArchive(archive.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp Verified')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'WhatsApp Verified',
              subtitle: _archives.isEmpty
                  ? 'Verified businesses uploaded from the web app will show up here'
                  : '${_archives.length} verified batch${_archives.length == 1 ? '' : 'es'}',
              trailing: HeaderBadge(
                icon: AppIcons.shieldCheck,
                background: t.sageTint,
                foreground: t.sageDeep,
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
                    MaterialPageRoute(builder: (_) => const WhatsAppVerifiedLeadsPage()),
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
                                  StateBadge(icon: AppIcons.shieldCheck, background: t.sageTint, foreground: t.sageDeep),
                                  const SizedBox(height: 20),
                                  Text('No verified businesses yet', style: Theme.of(context).textTheme.headlineSmall),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Validate WhatsApp numbers from an Excel Archive scan on the web app, '
                                    'then upload the verified list — it shows up here.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                              itemCount: _archives.length,
                              itemBuilder: (context, i) => _VerifiedArchiveCard(
                                archive: _archives[i],
                                onDelete: () => _delete(_archives[i]),
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

class _VerifiedArchiveCard extends StatelessWidget {
  const _VerifiedArchiveCard({required this.archive, required this.onDelete});

  final ExcelArchive archive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.sage.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _VerifiedArchiveViewerPage(archive: archive)),
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
                child: Icon(AppIcons.shieldCheck, size: 18, color: t.sageDeep),
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
                      '${archive.totalLeads} verified · ${_timeAgo(archive.createdAt)}',
                      style: TextStyle(fontSize: 12, color: t.faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(AppIcons.trash, size: 18, color: t.faint),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedArchiveViewerPage extends StatefulWidget {
  const _VerifiedArchiveViewerPage({required this.archive});

  final ExcelArchive archive;

  @override
  State<_VerifiedArchiveViewerPage> createState() => _VerifiedArchiveViewerPageState();
}

class _VerifiedArchiveViewerPageState extends State<_VerifiedArchiveViewerPage> {
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
                    ? Center(child: Text('No businesses in this archive.', style: TextStyle(color: t.faint)))
                    : TabBarView(children: [for (final s in _sheets) _VerifiedSheetList(sheet: s)]),
      ),
    );
  }
}

class _VerifiedSheetList extends StatelessWidget {
  const _VerifiedSheetList({required this.sheet});

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
      itemBuilder: (context, i) => BusinessRowCard(row: sheet.rows[i], badgeLabel: 'WhatsApp Verified'),
    );
  }
}
