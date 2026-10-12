import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/email_validation_snapshot.dart';
import '../../domain/entities/excel_archive.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import '../widgets/email_lead_card.dart';
import '../widgets/email_outcome_summary.dart';
import '../widgets/state_scope_section.dart';

const _allCategories = 'All categories';
const _pollInterval = Duration(milliseconds: 1500);

/// The upload/export shape of an email-verified business — the standard
/// lead JSON plus its verified address, written to the archive's Email
/// columns by the backend.
Map<String, dynamic> _leadToJson(Lead lead) {
  return {
    'business': lead.business,
    'phone': lead.phone,
    'hasWhatsApp': lead.hasWhatsApp,
    'waLink': lead.waLink,
    'website': lead.website,
    'location': lead.location,
    'address': lead.address,
    'category': lead.category,
    'rating': lead.rating,
    'mapsUrl': lead.mapsUrl,
    'email': lead.email,
    'emails': lead.emails,
    'emailSource': lead.emailSource,
    'badReview': {
      'text': lead.badReview.text,
      'date': lead.badReview.date,
    },
  };
}

/// The email counterpart to the WhatsApp validator on
/// [ExcelArchiveLeadsPage]: takes one Excel archive's businesses, and for a
/// chosen category (and optionally states) crawls each business's website
/// for a contact email and verifies it's deliverable. Verified businesses
/// are saved to the Email Leads list and uploaded as their own
/// "Email Verified" archive when the run finishes.
///
/// Nothing is sent to anyone — this only reads each business's public site.
class ExcelArchiveEmailValidatorPage extends StatefulWidget {
  const ExcelArchiveEmailValidatorPage({
    super.key,
    required this.archive,
    this.autoValidate = false,
  });

  final ExcelArchive archive;

  /// Jumps straight to the "Validate emails?" confirmation once the
  /// archive's (sole) category is known — the shortcut the Excel Archive
  /// list's "Validate emails" button uses.
  final bool autoValidate;

  @override
  State<ExcelArchiveEmailValidatorPage> createState() => _ExcelArchiveEmailValidatorPageState();
}

class _ExcelArchiveEmailValidatorPageState extends State<ExcelArchiveEmailValidatorPage> {
  List<Lead> _leads = [];
  bool _loading = true;
  String? _error;
  String _category = _allCategories;
  bool _autoValidateTriggered = false;

  Timer? _timer;
  EmailValidationSnapshot? _snapshot;
  bool _validating = false;
  List<Lead> _validatingLeads = [];
  String _validatingCategory = '';

  final Map<String, List<Lead>> _verifiedByCategory = {};
  bool _uploading = false;
  String? _uploadError;
  bool _allStates = true;
  final Set<String> _selectedStates = {};

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      // The dropdown only shows for multi-category archives, so a
      // single-category one must select its sole category itself or the
      // validate button (which needs a specific category) is unreachable.
      final cats = _categories;
      if (cats.length == 2) setState(() => _category = cats[1]);
      if (widget.autoValidate && !_autoValidateTriggered && _category != _allCategories) {
        _autoValidateTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startValidation(_inCategory);
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

  List<Lead> get _inCategory =>
      _category == _allCategories ? _leads : _leads.where((l) => l.category == _category).toList();

  List<Lead> _applyStateFilter(List<Lead> leads) {
    if (_allStates) return leads;
    return leads.where((l) => _selectedStates.contains(stateLabelOf(l.location))).toList();
  }

  bool _hasWebsite(Lead l) => l.website?.trim().isNotEmpty ?? false;

  int get _totalVerified => _verifiedByCategory.values.fold(0, (sum, l) => sum + l.length);

  Future<void> _startValidation(List<Lead> candidates) async {
    final inScope = _applyStateFilter(candidates);
    final eligible = inScope.where(_hasWebsite).toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _allStates
                ? 'None of these businesses have a website to check.'
                : _selectedStates.isEmpty
                    ? 'Pick one or more states first.'
                    : 'No websites in the selected states.',
          ),
        ),
      );
      return;
    }

    final scope = _allStates
        ? '"$_category"'
        : '${_selectedStates.length} selected state${_selectedStates.length == 1 ? '' : 's'} in "$_category"';
    final skipped = inScope.length - eligible.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validate emails?'),
        content: Text(
          'Looks for a contact email on ${eligible.length} business '
          'website${eligible.length == 1 ? '' : 's'} in $scope and checks each address is '
          'deliverable (roughly ${(eligible.length * 1.5 / 60).ceil()}-'
          '${(eligible.length * 3 / 60).ceil()} min). '
          '${skipped > 0 ? '$skipped without a website will be skipped. ' : ''}'
          'Nothing is sent to anyone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Validate')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _repo.validateEmailLeads([
        for (final l in eligible)
          {
            'id': l.id,
            'website': l.website,
            'business': l.business,
            'phone': l.phone,
            'category': l.category,
            'location': l.location,
            'address': l.address,
            'mapsUrl': l.mapsUrl,
            'rating': l.rating,
            'totalReviews': l.totalReviews,
          },
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
      _snapshot = null;
    });
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final snap = await _repo.getEmailValidationStatus();
      if (!mounted) return;
      setState(() => _snapshot = snap);
      if (snap.status == 'running') return;

      _timer?.cancel();
      final verified = [
        for (final l in _validatingLeads)
          if (snap.results[l.id]?.valid == true)
            l.copyWith(
              email: snap.results[l.id]!.email,
              emails: snap.results[l.id]!.emails,
              emailSource: snap.results[l.id]!.source,
            ),
      ];
      setState(() {
        _validating = false;
        _verifiedByCategory[_validatingCategory] = verified;
      });
      if (snap.status == 'done' && verified.isNotEmpty) {
        await _uploadVerified();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            verified.isEmpty
                ? 'Validation complete — no verified emails found in "$_validatingCategory".'
                : 'Validation stopped — ${verified.length} verified in "$_validatingCategory" were not uploaded.',
          ),
        ),
      );
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _validating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _cancel() async {
    try {
      await _repo.cancelEmailValidation();
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _uploadVerified() async {
    if (_totalVerified == 0 || _uploading) return;
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final archive = await _repo.uploadEmailVerifiedArchive(
        sheets: [
          for (final entry in _verifiedByCategory.entries)
            if (entry.value.isNotEmpty)
              {'name': entry.key, 'leads': entry.value.map(_leadToJson).toList()},
        ],
        sourceArchiveId: widget.archive.id,
        sourceFileName: widget.archive.fileName,
        countries: widget.archive.countries,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Validation complete — ${archive.totalLeads} verified emails saved.'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.push('/email-verified'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadError = e.toString().replaceFirst('Exception: ', ''));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_uploadError!),
          action: SnackBarAction(label: 'Retry', onPressed: _uploadVerified),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _inCategory;
    final verifiedHere = _verifiedByCategory[_category] ?? const <Lead>[];
    final withWebsite = _applyStateFilter(filtered).where(_hasWebsite).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Validate emails'),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Saving verified…'),
                ],
              ),
            )
          else if (_uploadError != null)
            TextButton.icon(
              onPressed: _uploadVerified,
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
                          child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                        ),
                      )
                    : _leads.isEmpty
                        ? const Center(
                            child: Text('This archive has no businesses.',
                                style: TextStyle(color: AppTheme.faint)),
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
                                'Only businesses with a website can be checked for an email.',
                                style: TextStyle(fontSize: 12, color: AppTheme.faint),
                              ),
                              if (_categories.length > 2) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _category,
                                  isExpanded: true,
                                  icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                                  decoration: const InputDecoration(labelText: 'Category'),
                                  items: _categories
                                      .map((c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(c, overflow: TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: _validating
                                      ? null
                                      : (v) {
                                          if (v != null) {
                                            setState(() {
                                              _category = v;
                                              _selectedStates.clear();
                                              _allStates = true;
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
                              _ValidationCard(
                                category: _category,
                                validating: _validating,
                                snapshot: _snapshot,
                                verifiedCount: verifiedHere.length,
                                eligibleCount: withWebsite,
                                canValidate: _category != _allCategories &&
                                    !_validating &&
                                    (_allStates || _selectedStates.isNotEmpty),
                                onValidate: () => _startValidation(filtered),
                                onCancel: _cancel,
                              ),
                              if (!_validating && _snapshot != null && _snapshot!.hasJob) ...[
                                const SizedBox(height: 12),
                                EmailOutcomeSummary(snapshot: _snapshot!),
                              ],
                              if (verifiedHere.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Icon(AppIcons.shieldCheck, size: 16, color: AppTheme.sage700),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Email Verified (${verifiedHere.length})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(color: AppTheme.sage800),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 14,
                                  runSpacing: 14,
                                  children: [
                                    for (final lead in verifiedHere)
                                      SizedBox(
                                        width: 340,
                                        height: 262,
                                        child: EmailLeadCard(lead: lead, onTap: () {}),
                                      ),
                                  ],
                                ),
                              ],
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
    required this.verifiedCount,
    required this.eligibleCount,
    required this.canValidate,
    required this.onValidate,
    required this.onCancel,
  });

  final String category;
  final bool validating;
  final EmailValidationSnapshot? snapshot;
  final int verifiedCount;
  final int eligibleCount;
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
        decoration: BoxDecoration(
          color: AppTheme.neutral100,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
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
                        ? 'Starting email validation…'
                        : 'Validating "$category" — ${snap.checked}/${snap.total} checked · '
                            '${snap.validCount} verified'
                            '${snap.noEmailCount > 0 ? ' · ${snap.noEmailCount} no email' : ''}'
                            '${snap.errorCount > 0 ? ' · ${snap.errorCount} unreachable' : ''}',
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
            if (snap?.currentLeadBusiness != null) ...[
              const SizedBox(height: 8),
              Text(
                'Checking ${snap!.currentLeadBusiness}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppTheme.faint),
              ),
            ],
          ],
        ),
      );
    }

    final pickCategory = category == _allCategories;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.neutral200),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: AppTheme.sage100, shape: BoxShape.circle),
            child: const Icon(AppIcons.mail, size: 17, color: AppTheme.sage700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pickCategory ? 'Select a category to validate' : 'Validate emails for "$category"',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  pickCategory
                      ? 'Pick a specific category above first — validation runs per category.'
                      : verifiedCount > 0
                          ? '$verifiedCount already verified in this category · re-run to refresh'
                          : '$eligibleCount business${eligibleCount == 1 ? '' : 'es'} with a website '
                              'will be checked for a deliverable contact email.',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: canValidate ? onValidate : null,
            icon: const Icon(AppIcons.mail, size: 16),
            label: const Text('Validate'),
          ),
        ],
      ),
    );
  }
}
