import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../widgets/lead_card.dart';

const _allCategories = 'All categories';
const _pollInterval = Duration(milliseconds: 1500);

Map<String, dynamic> _leadToJson(Lead lead) {
  return {
    'business': lead.business,
    'phone': lead.phone,
    'hasWhatsApp': true,
    'waLink': lead.waLink ?? 'https://wa.me/${(lead.phone ?? '').replaceAll(RegExp(r'\D'), '')}',
    'website': lead.website,
    'location': lead.location,
    'address': lead.address,
    'category': lead.category,
    'rating': lead.rating,
    'mapsUrl': lead.mapsUrl,
    'badReview': {
      'text': lead.badReview.text,
      'date': lead.badReview.date,
    },
  };
}

/// Extracts every business in an Excel archive and shows it with the same
/// `LeadCard` widget used everywhere else in the app. These businesses were
/// never saved to Firestore — that's the whole point of an `exportOnly`
/// scan — so this is a read-only view built straight from the archived
/// workbook, not a query against saved leads.
///
/// A multi-category (and/or multi-country) archive has one workbook sheet
/// per category — [Lead.category] carries that sheet's name straight
/// through from the backend, so the dropdown here just groups by it rather
/// than re-deriving anything. A "Validate WhatsApp" action runs the real
/// guarded WhatsApp Web checker over the selected category's businesses,
/// building up a verified list per category that can be uploaded as its
/// own archive once you're happy with it.
class ExcelArchiveLeadsPage extends StatefulWidget {
  const ExcelArchiveLeadsPage({super.key, required this.archive, this.autoValidate = false});

  final ExcelArchive archive;

  /// Jumps straight to the "Validate WhatsApp numbers?" confirmation the
  /// moment the archive's (sole) category is known — the shortcut the
  /// Excel Archive list's "Validate WhatsApp" button uses, so it doesn't
  /// just land here and require an extra click to find the same button.
  final bool autoValidate;

  @override
  State<ExcelArchiveLeadsPage> createState() => _ExcelArchiveLeadsPageState();
}

class _ExcelArchiveLeadsPageState extends State<ExcelArchiveLeadsPage> {
  List<Lead> _leads = [];
  bool _loading = true;
  String? _error;
  String _category = _allCategories;
  bool _autoValidateTriggered = false;

  Timer? _validationTimer;
  WhatsAppValidationSnapshot? _validationSnapshot;
  bool _validating = false;
  List<Lead> _validatingLeads = [];
  String _validatingCategory = '';

  final Map<String, List<Lead>> _validatedByCategory = {};
  bool _uploading = false;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final leads = await _repo.getExcelArchiveLeads(widget.archive.id);
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _loading = false;
      });
      // The category dropdown only renders when there's more than one real
      // category to choose between (see build()) — for the current, purely
      // single-category scan engine that means it never appears, which
      // silently made "Validate WhatsApp" unreachable (it requires a
      // specific category, not "All categories"). Auto-selecting the sole
      // category here fixes that for every archive, not just the
      // auto-validate shortcut below.
      final cats = _categories;
      if (cats.length == 2) {
        setState(() => _category = cats[1]);
      }
      if (widget.autoValidate && !_autoValidateTriggered && _category != _allCategories) {
        _autoValidateTriggered = true;
        final filtered = _leads.where((l) => l.category == _category).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startValidation(filtered);
        });
      }
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
    for (final l in _leads) {
      final c = l.category.trim();
      if (c.isNotEmpty) present.add(c);
    }
    final sorted = present.toList()..sort();
    return [_allCategories, ...sorted];
  }

  int get _totalValidated => _validatedByCategory.values.fold(0, (sum, l) => sum + l.length);

  Future<void> _startValidation(List<Lead> candidates) async {
    WhatsAppWebStatus webStatus;
    try {
      webStatus = await _repo.getWhatsAppWebStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    if (!mounted) return;

    if (!webStatus.isReady) {
      final goConnect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp Web not connected'),
          content: const Text(
            'Real WhatsApp validation needs a linked WhatsApp Web session. '
            'Connect it from the WhatsApp Tool page, then come back here.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Go connect')),
          ],
        ),
      );
      if (goConnect == true && mounted) {
        context.go('/whatsapp');
      }
      return;
    }

    final blockedReason = webStatus.safety.blockedReason;
    if (blockedReason != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp checks paused'),
          content: Text(
            '$blockedReason\n\nThis keeps the linked WhatsApp account from getting '
            'flagged for automated-looking activity — it resets on its own.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final eligible = candidates.where((l) => (l.phone?.trim().isNotEmpty ?? false)).toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('None of these businesses have a phone number to check.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validate WhatsApp numbers?'),
        content: Text(
          'Checks ${eligible.length} business${eligible.length == 1 ? '' : 'es'} in "$_category" '
          'against your connected WhatsApp Web session (roughly ${(eligible.length * 3 / 60).ceil()}-'
          '${(eligible.length * 6 / 60).ceil()} min). No messages are sent.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Validate')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _repo.validateExternalLeads([
        for (final l in eligible) {'id': l.id, 'phone': l.phone!, 'business': l.business},
      ]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }

    setState(() {
      _validating = true;
      _validatingLeads = eligible;
      _validatingCategory = _category;
      _validationSnapshot = null;
    });
    _pollValidation();
    _validationTimer = Timer.periodic(_pollInterval, (_) => _pollValidation());
  }

  Future<void> _pollValidation() async {
    try {
      final snap = await _repo.getWhatsAppValidationStatus();
      if (!mounted) return;
      setState(() => _validationSnapshot = snap);
      if (snap.status != 'running') {
        _validationTimer?.cancel();
        final validated = _validatingLeads
            .where((l) => snap.results[l.id]?.valid == true)
            .map((l) => l.copyWith(hasWhatsApp: true))
            .toList();
        setState(() {
          _validating = false;
          _validatedByCategory[_validatingCategory] = validated;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              validated.isEmpty
                  ? 'Validation complete — no WhatsApp numbers found in "$_validatingCategory".'
                  : 'Validation complete — ${validated.length} verified in "$_validatingCategory".',
            ),
          ),
        );
      }
    } catch (e) {
      _validationTimer?.cancel();
      if (!mounted) return;
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _cancelValidation() async {
    try {
      await _repo.cancelWhatsAppValidation();
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _uploadValidated() async {
    if (_totalValidated == 0 || _uploading) return;
    setState(() => _uploading = true);
    try {
      final sheets = [
        for (final entry in _validatedByCategory.entries)
          if (entry.value.isNotEmpty)
            {'name': entry.key, 'leads': entry.value.map(_leadToJson).toList()},
      ];
      final archive = await _repo.uploadValidatedArchive(
        sheets: sheets,
        sourceArchiveId: widget.archive.id,
        sourceFileName: widget.archive.fileName,
        countries: widget.archive.countries,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploaded ${archive.totalLeads} verified businesses to Firebase.'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.push('/whatsapp-verified'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _category == _allCategories
        ? _leads
        : _leads.where((l) => l.category == _category).toList();
    final validatedHere = _validatedByCategory[_category] ?? const <Lead>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Businesses in Archive'),
        actions: [
          if (_totalValidated > 0) ...[
            TextButton.icon(
              onPressed: _uploading ? null : _uploadValidated,
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.cloudUpload, size: 18),
              label: Text(_uploading ? 'Uploading…' : 'Upload Verified ($_totalValidated)'),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                        ),
                      )
                    : _leads.isEmpty
                        ? const Center(
                            child: Text('This archive has no businesses.', style: TextStyle(color: AppTheme.faint)),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                            children: [
                              Text(
                                '${_leads.length} businesses · ${widget.archive.fileName}',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.ink,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Extracted from the Excel archive — not saved to Firestore.',
                                style: TextStyle(fontSize: 12, color: AppTheme.faint),
                              ),
                              if (_categories.length > 2) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _category,
                                  icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                                  decoration: const InputDecoration(labelText: 'Category'),
                                  items: _categories
                                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: _validating
                                      ? null
                                      : (v) {
                                          if (v != null) setState(() => _category = v);
                                        },
                                ),
                              ],
                              const SizedBox(height: 16),
                              _ValidationCard(
                                category: _category,
                                validating: _validating,
                                snapshot: _validationSnapshot,
                                validatedCount: validatedHere.length,
                                canValidate: _category != _allCategories && !_validating,
                                onValidate: () => _startValidation(filtered),
                                onCancel: _cancelValidation,
                              ),
                              if (validatedHere.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Icon(AppIcons.shieldCheck, size: 16, color: AppTheme.sage700),
                                    const SizedBox(width: 8),
                                    Text(
                                      'WhatsApp Verified (${validatedHere.length})',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.sage800),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...validatedHere.map((lead) => _VerifiedLeadTile(lead: lead)),
                              ],
                              const SizedBox(height: 20),
                              Text(
                                'All businesses · ${filtered.length} of ${_leads.length} shown',
                                style: const TextStyle(fontSize: 12, color: AppTheme.faint, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              ...filtered.map((lead) => LeadCard(lead: lead)),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({
    required this.category,
    required this.validating,
    required this.snapshot,
    required this.validatedCount,
    required this.canValidate,
    required this.onValidate,
    required this.onCancel,
  });

  final String category;
  final bool validating;
  final WhatsAppValidationSnapshot? snapshot;
  final int validatedCount;
  final bool canValidate;
  final VoidCallback onValidate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    if (validating) {
      final snap = snapshot;
      final fraction = (snap != null && snap.total > 0) ? snap.checked / snap.total : 0.0;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppTheme.neutral100, borderRadius: BorderRadius.circular(AppTheme.radius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    snap == null
                        ? 'Starting WhatsApp validation…'
                        : 'Validating "$category" — ${snap.checked}/${snap.total} checked · ${snap.validCount} verified',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.subtle),
                  ),
                ),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: LinearProgressIndicator(value: fraction, minHeight: 6),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radius), border: Border.all(color: AppTheme.neutral200)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: AppTheme.sage100, shape: BoxShape.circle),
            child: const Icon(AppIcons.chat, size: 17, color: AppTheme.sage700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category == _allCategories ? 'Select a category to validate' : 'Validate WhatsApp for "$category"',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  category == _allCategories
                      ? 'Pick a specific category above first — validation runs per category.'
                      : validatedCount > 0
                          ? '$validatedCount already verified in this category · re-run to refresh'
                          : 'Checks each business\'s number against your linked WhatsApp session.',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: canValidate ? onValidate : null,
            icon: const Icon(AppIcons.chat, size: 16),
            label: const Text('Validate'),
          ),
        ],
      ),
    );
  }
}

/// A `LeadCard` with a small "WhatsApp Verified" badge above it — the
/// card itself doesn't otherwise distinguish a validated business from an
/// unchecked one.
class _VerifiedLeadTile extends StatelessWidget {
  const _VerifiedLeadTile({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.sage300),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard + 3),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.checkCircle, size: 13, color: AppTheme.sage700),
                const SizedBox(width: 5),
                const Text(
                  'WhatsApp Verified',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.sage700),
                ),
              ],
            ),
          ),
          LeadCard(lead: lead),
        ],
      ),
    );
  }
}
