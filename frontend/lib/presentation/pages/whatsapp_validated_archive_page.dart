import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../widgets/lead_card.dart';

String _timeAgo(DateTime? when) {
  if (when == null) return '';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Browses businesses that passed real WhatsApp Web validation and were
/// uploaded from the Excel Archive's "Upload Verified" action — a separate
/// Firebase collection from the source Excel scans, holding only confirmed
/// WhatsApp-registered numbers. Available on web and mobile.
class WhatsAppValidatedArchivePage extends StatefulWidget {
  const WhatsAppValidatedArchivePage({super.key});

  @override
  State<WhatsAppValidatedArchivePage> createState() => _WhatsAppValidatedArchivePageState();
}

class _WhatsAppValidatedArchivePageState extends State<WhatsAppValidatedArchivePage> {
  List<ExcelArchive> _archives = [];
  bool _loading = true;
  String? _error;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final archives = await _repo.listValidatedArchives();
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
      await _repo.deleteValidatedArchive(archive.id);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Verified'),
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
                        ? const _EmptyState()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                            children: [
                              for (final archive in _archives)
                                _VerifiedArchiveCard(
                                  archive: archive,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => _VerifiedArchiveViewerPage(archive: archive)),
                                  ),
                                  onDelete: () => _delete(archive),
                                ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              decoration: const BoxDecoration(color: AppTheme.sage100, shape: BoxShape.circle),
              child: const Icon(AppIcons.shieldCheck, size: 30, color: AppTheme.sage700),
            ),
            const SizedBox(height: 16),
            Text('No verified businesses yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Validate WhatsApp numbers from an Excel Archive scan, then upload the '
              'verified list — it shows up here.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerifiedArchiveCard extends StatelessWidget {
  const _VerifiedArchiveCard({required this.archive, required this.onTap, required this.onDelete});

  final ExcelArchive archive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.sage300),
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
                child: const Icon(AppIcons.shieldCheck, size: 18, color: AppTheme.sage700),
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
                      style: const TextStyle(fontSize: 12, color: AppTheme.faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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

class _VerifiedArchiveViewerPage extends StatefulWidget {
  const _VerifiedArchiveViewerPage({required this.archive});

  final ExcelArchive archive;

  @override
  State<_VerifiedArchiveViewerPage> createState() => _VerifiedArchiveViewerPageState();
}

class _VerifiedArchiveViewerPageState extends State<_VerifiedArchiveViewerPage> {
  List<Lead> _leads = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final leads = await context.read<LeadRepository>().getValidatedArchiveLeads(widget.archive.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.archive.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Download .xlsx',
            icon: const Icon(AppIcons.download),
            onPressed: () => launchUrl(Uri.parse(widget.archive.downloadUrl)),
          ),
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
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                    : _leads.isEmpty
                        ? const Center(child: Text('No businesses in this archive.', style: TextStyle(color: AppTheme.faint)))
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                            children: [
                              Row(
                                children: [
                                  const Icon(AppIcons.shieldCheck, size: 16, color: AppTheme.sage700),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_leads.length} WhatsApp-verified businesses',
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.sage800,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ..._leads.map((lead) => LeadCard(lead: lead)),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}
