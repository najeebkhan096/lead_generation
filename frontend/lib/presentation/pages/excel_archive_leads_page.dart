import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/email_validation.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/validation_start.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../design_system/design_system.dart';
import '../utils/lazy_reveal.dart';
import '../widgets/lead_card.dart';
import '../widgets/state_scope_section.dart';

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
/// building up a verified list per category that is uploaded as its
/// own archive automatically when validation finishes.
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

class _ExcelArchiveLeadsPageState extends State<ExcelArchiveLeadsPage> with LazyRevealMixin {
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
  String? _uploadError;
  bool _allStates = true;
  final Set<String> _selectedStates = {};

  /// This archive's validations that stopped before finishing (cancelled,
  /// halted for a safety reason, or cut off by a backend restart).
  List<ValidationRun> _unfinished = const [];

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    initReveal();
    _load();
    _loadUnfinished();
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    disposeReveal();
    super.dispose();
  }

  /// What an interrupted validation of THIS archive had been doing, if anything.
  Future<void> _loadUnfinished() async {
    try {
      final runs = await _repo.listValidationRuns(collection: 'archive', kind: 'whatsapp');
      if (mounted) setState(() => _unfinished = [for (final r in runs) if (r.archiveId == widget.archive.id) r]);
    } catch (_) {
      // A convenience: validating again by hand also skips what is already answered.
    }
  }

  /// Carries on a stopped validation: same category and states, asking only about
  /// the numbers that have no answer yet (the backend remembers the ones that do).
  Future<void> _resume(ValidationRun run) async {
    final category = run.category;
    if (category == null || !_categories.contains(category)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That validation\'s category is not in this archive any more.')),
      );
      return;
    }
    setState(() {
      _category = category;
      _allStates = run.states.isEmpty;
      _selectedStates
        ..clear()
        ..addAll(run.states);
    });
    final filtered = _leads.where((l) => l.category == category).toList();
    final before = _validating;
    await _startValidation(filtered, resuming: run);
    // Started: the new run is on record, so the old one is done with.
    if (!before && _validating) {
      try {
        await _repo.discardValidationRun(run.id);
      } catch (_) {
        // harmless: it shows as unfinished until the next load
      }
      await _loadUnfinished();
    }
  }

  Future<void> _discard(ValidationRun run) async {
    try {
      await _repo.discardValidationRun(run.id);
    } catch (_) {}
    await _loadUnfinished();
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

  List<Lead> _applyStateFilter(List<Lead> leads) {
    if (_allStates) return leads;
    return leads.where((l) => _selectedStates.contains(stateLabelOf(l.location))).toList();
  }

  int get _totalValidated => _validatedByCategory.values.fold(0, (sum, l) => sum + l.length);

  Future<void> _startValidation(List<Lead> candidates, {ValidationRun? resuming}) async {
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

    final eligible = _applyStateFilter(candidates).where((l) => (l.phone?.trim().isNotEmpty ?? false)).toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _allStates
                ? 'None of these businesses have a phone number to check.'
                : _selectedStates.isEmpty
                    ? 'Pick one or more states first.'
                    : 'No phone numbers in the selected states.',
          ),
        ),
      );
      return;
    }

    final scope = _allStates
        ? '"$_category"'
        : '${_selectedStates.length} selected state${_selectedStates.length == 1 ? '' : 's'} in "$_category"';
    var recheck = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(resuming == null ? 'Validate WhatsApp numbers?' : 'Resume validating WhatsApp numbers?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Checks up to ${eligible.length} business${eligible.length == 1 ? '' : 'es'} in $scope '
                'against your connected WhatsApp Web session (roughly ${(eligible.length * 3 / 60).ceil()}-'
                '${(eligible.length * 6 / 60).ceil()} min). Numbers already answered earlier are not '
                'asked again — verified ones are kept, and ones found not to be on WhatsApp are skipped. '
                'No messages are sent.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: recheck,
                onChanged: (v) => setLocal(() => recheck = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Re-ask every number, including ones checked before'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Validate')),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    // The whole lead, not just its phone: a verified number is copied into
    // the WhatsApp leads collection with these details.
    final payload = [
      for (final l in eligible)
        {
          'id': l.id,
          'phone': l.phone!,
          'business': l.business,
          'category': l.category,
          'location': l.location,
          'address': l.address,
          'website': l.website,
          'mapsUrl': l.mapsUrl,
          'rating': l.rating,
          'totalReviews': l.totalReviews,
          'badReview': {'text': l.badReview.text, 'date': l.badReview.date},
        },
    ];
    // What is being validated, so a stop or a restart leaves a run to resume.
    final runScope = {
      'archiveId': widget.archive.id,
      'category': _category,
      'states': _allStates ? <String>[] : _selectedStates.toList(),
    };
    try {
      final start = await _repo.validateExternalLeads(payload, recheck: recheck, scope: runScope);
      final summary = start.summary;
      if (summary != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
      }
    } on AlreadyCheckedException catch (e) {
      if (!mounted) return;
      final again = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already checked'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Re-check anyway')),
          ],
        ),
      );
      if (again != true || !mounted) return;
      try {
        await _repo.validateExternalLeads(payload, recheck: true, scope: runScope);
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
          );
        }
        return;
      }
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
        _loadUnfinished(); // it may have stopped early
        final validated = _validatingLeads
            .where((l) => snap.results[l.id]?.valid == true)
            .map((l) => l.copyWith(hasWhatsApp: true))
            .toList();
        setState(() {
          _validating = false;
          _validatedByCategory[_validatingCategory] = validated;
        });
        if (!mounted) return;
        if (snap.status == 'done' && validated.isNotEmpty) {
          await _uploadValidated();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              validated.isEmpty
                  ? 'Validation complete — no WhatsApp numbers found in "$_validatingCategory".'
                  : 'Validation stopped — ${validated.length} verified in "$_validatingCategory" were not uploaded.',
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
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
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
          content: Text('Validation complete — uploaded ${archive.totalLeads} verified businesses.'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.push('/whatsapp-verified'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadError = e.toString().replaceFirst('Exception: ', ''));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_uploadError!),
          action: SnackBarAction(label: 'Retry', onPressed: _uploadValidated),
        ),
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
          if (_uploading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Uploading verified…'),
                ],
              ),
            )
          else if (_uploadError != null)
            TextButton.icon(
              onPressed: _uploadValidated,
              icon: const Icon(AppIcons.cloudUpload, size: 18),
              label: const Text('Retry upload'),
            ),
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
                          child: Text(_error!, style: TextStyle(color: AppTheme.error)),
                        ),
                      )
                    : _leads.isEmpty
                        ? Center(
                            child: Text('This archive has no businesses.', style: TextStyle(color: AppTheme.textMuted)),
                          )
                        : ListView(
                            controller: revealController,
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                            children: [
                              Text(
                                '${_leads.length} businesses · ${widget.archive.fileName}',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Extracted from the Excel archive — not saved to Firestore.',
                                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                              if (_categories.length > 2) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _category,
                                  icon: Icon(AppIcons.chevronDown, size: 18, color: AppTheme.primary),
                                  decoration: const InputDecoration(labelText: 'Category'),
                                  items: _categories
                                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: _validating
                                      ? null
                                      : (v) {
                                          if (v != null) {
                                            setState(() {
                                              _category = v;
                                              _selectedStates.clear();
                                              _allStates = true;
                                              revealCount = LazyRevealMixin.revealStep;
                                            });
                                          }
                                        },
                                ),
                              ],
                              const SizedBox(height: 16),
                              if (filtered.isNotEmpty)
                                StateScopeSection(
                                  states: statesIn(filtered),
                                  allStates: _allStates,
                                  selected: _selectedStates,
                                  enabled: !_validating,
                                  onAllChanged: (all) => setState(() => _allStates = all),
                                  onToggle: (name, selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedStates.add(name);
                                      } else {
                                        _selectedStates.remove(name);
                                      }
                                    });
                                  },
                                ),
                              const SizedBox(height: 16),
                              if (!_validating)
                                for (final run in _unfinished) ...[
                                  _UnfinishedRun(
                                    run: run,
                                    onResume: () => _resume(run),
                                    onDiscard: () => _discard(run),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              _ValidationCard(
                                category: _category,
                                validating: _validating,
                                snapshot: _validationSnapshot,
                                validatedCount: validatedHere.length,
                                canValidate: _category != _allCategories &&
                                    !_validating &&
                                    (_allStates || _selectedStates.isNotEmpty),
                                onValidate: () => _startValidation(filtered),
                                onCancel: _cancelValidation,
                              ),
                              if (validatedHere.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Icon(AppIcons.shieldCheck, size: 16, color: AppTheme.success700),
                                    const SizedBox(width: 8),
                                    Text(
                                      'WhatsApp Verified (${validatedHere.length})',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.success800),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...validatedHere.map((lead) => _VerifiedLeadTile(lead: lead)),
                              ],
                              const SizedBox(height: 20),
                              Text(
                                'All businesses · ${filtered.length} of ${_leads.length} shown',
                                style: TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              // Only a window of cards is built; it grows as you scroll.
                              ...filtered.take(revealCount).map((lead) => LeadCard(lead: lead)),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}

/// A validation of this archive that stopped before it finished: what it was,
/// how far it got, and a way to carry on from there.
class _UnfinishedRun extends StatelessWidget {
  const _UnfinishedRun({required this.run, required this.onResume, required this.onDiscard});

  final ValidationRun run;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return AppAlert(
      tone: AppTone.warning,
      title: run.status == 'interrupted' ? 'Interrupted validation' : 'Stopped validation',
      message: [
        if (run.category != null) '"${run.category}"',
        run.states.isEmpty ? 'every state' : run.states.join(', '),
        '${run.checked} of ${run.total} checked',
        if (run.found > 0) '${run.found} on WhatsApp',
        if (run.stoppedReason != null && run.stoppedReason!.isNotEmpty)
          run.stoppedReason!
        else if (run.status == 'interrupted')
          'the backend stopped while it was running',
      ].join(' · '),
      actions: [
        AppButton.primary(label: 'Resume', icon: AppIcons.refresh, size: AppButtonSize.sm, onPressed: onResume),
        AppButton.outlined(label: 'Discard', size: AppButtonSize.sm, onPressed: onDiscard),
      ],
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
                        : (snap.errorCount > 0
                            ? 'Validating "$category" — ${snap.checked}/${snap.total} checked · ${snap.validCount} verified · ${snap.errorCount} errors'
                            : 'Validating "$category" — ${snap.checked}/${snap.total} checked · ${snap.validCount} verified'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary),
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
            if (snap?.stoppedReason != null && snap!.stoppedReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                snap.stoppedReason!,
                style: TextStyle(fontSize: 12, color: AppTheme.primary700),
              ),
            ],
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
            decoration: BoxDecoration(color: AppTheme.success100, shape: BoxShape.circle),
            child: Icon(AppIcons.chat, size: 17, color: AppTheme.success700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category == _allCategories ? 'Select a category to validate' : 'Validate WhatsApp for "$category"',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  category == _allCategories
                      ? 'Pick a specific category above first — validation runs per category.'
                      : validatedCount > 0
                          ? '$validatedCount already verified in this category · re-run to refresh'
                          : 'Checks each business\'s number against your linked WhatsApp session.',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
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
        border: Border.all(color: AppTheme.success300),
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
                Icon(AppIcons.checkCircle, size: 13, color: AppTheme.success700),
                const SizedBox(width: 5),
                Text(
                  'WhatsApp Verified',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.success700),
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
