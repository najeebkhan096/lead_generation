import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/sales_user.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../../domain/repositories/lead_repository.dart';

String _timeAgo(DateTime? when) {
  if (when == null) return 'Never scanned';
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Manually-curated list of specific client businesses (added by their
/// Google Maps URL), re-scanned on demand to surface any new reviews since
/// the last check. Scanning is a button press, not a background daily job —
/// the backend only runs while this app's Launcher is open, so "automatic
/// daily" scanning isn't reliable; the user triggers it whenever they want.
class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();

  List<WatchlistEntry> _entries = [];
  List<WatchlistScanResult> _lastResults = [];
  List<SalesUser> _salesmen = [];
  bool _loading = true;
  bool _adding = false;
  bool _scanning = false;
  String? _error;
  String _dateRange = '30';
  String? _selectedSalesmanId;

  static const _dateRanges = <String, String>{
    '30': 'Last 30 days',
    '45': 'Last 45 days',
    '60': 'Last 60 days',
    '90': 'Last 90 days',
    '180': 'Last 6 months',
  };

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
    _loadSalesmen();
  }

  Future<void> _loadSalesmen() async {
    try {
      final salesmen = await _repo.listSalesmen();
      if (!mounted) return;
      setState(() => _salesmen = salesmen);
    } catch (_) {
      // Non-critical — the add form just won't offer assignment.
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await _repo.listWatchlist();
      if (!mounted) return;
      setState(() {
        _entries = entries;
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

  Future<void> _add() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final salesman = _salesmen.where((s) => s.id == _selectedSalesmanId).firstOrNull;
    setState(() => _adding = true);
    try {
      await _repo.addWatchlistEntry(
        url: url,
        name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
        assignedTo: salesman?.id,
        assignedToName: salesman?.name,
      );
      _urlController.clear();
      _nameController.clear();
      setState(() => _selectedSalesmanId = null);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(WatchlistEntry entry) async {
    try {
      await _repo.deleteWatchlistEntry(entry.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _reassign(WatchlistEntry entry, SalesUser? salesman) async {
    try {
      await _repo.assignWatchlistEntry(entry.id, assignedTo: salesman?.id, assignedToName: salesman?.name);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _scanNow() async {
    if (_scanning || _entries.isEmpty) return;
    setState(() {
      _scanning = true;
      _lastResults = [];
    });
    try {
      final results = await _repo.scanWatchlist(dateRange: _dateRange);
      if (!mounted) return;
      final newReviewTotal = results.fold<int>(0, (sum, r) => sum + r.newReviews.length);
      setState(() => _lastResults = results);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newReviewTotal > 0
                ? 'Scan complete — $newReviewTotal new review${newReviewTotal == 1 ? '' : 's'} found.'
                : 'Scan complete — no new reviews.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.neutral100,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _dateRange,
                icon: const Icon(AppIcons.chevronDown, size: 16, color: AppTheme.subtle),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.ink),
                items: _dateRanges.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: _scanning
                    ? null
                    : (v) {
                        if (v != null) setState(() => _dateRange = v);
                      },
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: (_scanning || _entries.isEmpty) ? null : _scanNow,
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.refresh, size: 18),
            label: Text(_scanning ? 'Scanning…' : 'Scan Watchlist Now'),
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                    children: [
                      Text(
                        'Track your best clients',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add a business\'s Google Maps URL once, then hit "Scan '
                        'Watchlist Now" any time you want to check for new reviews. '
                        'This runs on demand — not automatically in the background.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      _AddForm(
                        urlController: _urlController,
                        nameController: _nameController,
                        adding: _adding,
                        onAdd: _add,
                        salesmen: _salesmen,
                        selectedSalesmanId: _selectedSalesmanId,
                        onSalesmanChanged: (v) => setState(() => _selectedSalesmanId = v),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                      ],
                      const SizedBox(height: 24),
                      if (_entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accent100,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(AppIcons.eye, size: 30, color: AppTheme.accent700),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No businesses tracked yet',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Paste a Google Maps business link above to start tracking it.',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        for (final entry in _entries)
                          _WatchlistCard(
                            entry: entry,
                            result: _lastResults.where((r) => r.id == entry.id).firstOrNull,
                            salesmen: _salesmen,
                            onDelete: () => _delete(entry),
                            onReassign: (s) => _reassign(entry, s),
                          ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AddForm extends StatelessWidget {
  const _AddForm({
    required this.urlController,
    required this.nameController,
    required this.adding,
    required this.onAdd,
    required this.salesmen,
    required this.selectedSalesmanId,
    required this.onSalesmanChanged,
  });

  final TextEditingController urlController;
  final TextEditingController nameController;
  final bool adding;
  final VoidCallback onAdd;
  final List<SalesUser> salesmen;
  final String? selectedSalesmanId;
  final ValueChanged<String?> onSalesmanChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: urlController,
            decoration: const InputDecoration(
              labelText: 'Google Maps business URL',
              hintText: 'https://www.google.com/maps/place/...',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'e.g. Acme Plumbing — main client',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: selectedSalesmanId,
            icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
            decoration: InputDecoration(
              labelText: 'Assign to salesman (optional)',
              prefixIcon: const Icon(AppIcons.users, size: 18),
              helperText: salesmen.isEmpty
                  ? 'No salesmen registered yet — they show up here once someone signs into the mobile app.'
                  : null,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
              for (final s in salesmen) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: onSalesmanChanged,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: adding ? null : onAdd,
              icon: adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.surface),
                    )
                  : const Icon(AppIcons.plus, size: 18),
              label: Text(adding ? 'Adding…' : 'Add to Watchlist'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchlistCard extends StatelessWidget {
  const _WatchlistCard({
    required this.entry,
    required this.result,
    required this.salesmen,
    required this.onDelete,
    required this.onReassign,
  });

  final WatchlistEntry entry;
  final WatchlistScanResult? result;
  final List<SalesUser> salesmen;
  final VoidCallback onDelete;
  final ValueChanged<SalesUser?> onReassign;

  @override
  Widget build(BuildContext context) {
    final hasNew = entry.lastNewReviewCount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: hasNew ? AppTheme.accent300 : AppTheme.neutral200),
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
                    Text(
                      entry.name?.isNotEmpty == true ? entry.name! : entry.url,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => launchUrl(Uri.parse(entry.url)),
                      child: Text(
                        entry.url,
                        style: const TextStyle(
                          color: AppTheme.faint,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(AppIcons.trash, size: 18, color: AppTheme.faint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PopupMenuButton<SalesUser?>(
                tooltip: 'Reassign',
                onSelected: onReassign,
                itemBuilder: (context) => [
                  const PopupMenuItem<SalesUser?>(value: null, child: Text('Unassigned')),
                  for (final s in salesmen) PopupMenuItem<SalesUser?>(value: s, child: Text(s.name)),
                ],
                child: _Chip(
                  icon: AppIcons.users,
                  label: entry.assignedToName ?? 'Unassigned',
                  color: entry.assignedToName != null ? AppTheme.sage700 : AppTheme.subtle,
                  background: entry.assignedToName != null ? AppTheme.sage100 : AppTheme.neutral100,
                ),
              ),
              _Chip(icon: AppIcons.clock, label: _timeAgo(entry.lastScannedAt)),
              if (entry.lastRating != null)
                _Chip(icon: AppIcons.star, label: '${entry.lastRating} (${entry.lastTotalReviews ?? 0})'),
              if (hasNew)
                _Chip(
                  icon: AppIcons.messageWarning,
                  label: '${entry.lastNewReviewCount} new review${entry.lastNewReviewCount == 1 ? '' : 's'}',
                  color: AppTheme.accent700,
                  background: AppTheme.accent100,
                ),
              if (entry.lastError != null)
                _Chip(
                  icon: AppIcons.alert,
                  label: entry.lastError!,
                  color: AppTheme.danger,
                  background: AppTheme.accent100,
                ),
            ],
          ),
          if (result != null && result!.newReviews.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.neutral200),
            const SizedBox(height: 12),
            for (final review in result!.newReviews) _ReviewTile(review: review),
          ],
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final WatchlistReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AppIcons.star,
            size: 15,
            color: (review.stars ?? 0) <= 2 ? AppTheme.accent700 : AppTheme.sage600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${review.reviewer} · ${review.stars ?? '?'}★ · ${review.date}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.subtle),
                      ),
                    ),
                    if (review.link != null)
                      InkWell(
                        onTap: () => launchUrl(Uri.parse(review.link!)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Open Review',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (review.text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(review.text, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.color = AppTheme.subtle,
    this.background = AppTheme.neutral100,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
