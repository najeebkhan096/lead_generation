import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/email_validation_snapshot.dart';
import '../../domain/entities/lead.dart';
import '../../domain/repositories/lead_repository.dart';
import 'email_outcome_summary.dart';

const _pollInterval = Duration(seconds: 2);

/// One run is capped by the backend; larger lists are validated in chunks.
const websiteLeadValidationBatch = 500;

/// "Validate emails" for the Website Leads list.
///
/// Website leads have no website, so there is nothing to crawl — the backend
/// looks each business up on the web by name, address and phone and keeps an
/// address only when the page it came from also shows the business's phone
/// (or its name and city). Coverage is therefore partial by design; a miss
/// beats a wrong address.
///
/// Works on [leads] (the list as currently filtered) and skips the ones that
/// already have an email. Calls [onFinished] once a run ends so the list can
/// reload and show the addresses that were written onto the leads.
class WebsiteLeadEmailValidator extends StatefulWidget {
  const WebsiteLeadEmailValidator({
    super.key,
    required this.leads,
    required this.onFinished,
    this.emailOnly = false,
    this.onEmailOnlyChanged,
  });

  final List<Lead> leads;
  final VoidCallback onFinished;
  final bool emailOnly;
  final ValueChanged<bool>? onEmailOnlyChanged;

  @override
  State<WebsiteLeadEmailValidator> createState() => _WebsiteLeadEmailValidatorState();
}

class _WebsiteLeadEmailValidatorState extends State<WebsiteLeadEmailValidator> {
  Timer? _timer;
  bool _running = false;
  EmailValidationSnapshot? _snapshot;
  EmailValidationSnapshot? _lastRun;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Lead> get _pending =>
      widget.leads.where((l) => l.dbId != null && (l.email == null || l.email!.isEmpty)).toList();

  int get _withEmail => widget.leads.where((l) => l.email != null && l.email!.isNotEmpty).length;

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start() async {
    final pending = _pending;
    if (pending.isEmpty) return;
    final batch = pending.take(websiteLeadValidationBatch).toList();
    final minutes = (batch.length * 2.5 / 60).ceil();
    final maxMinutes = (batch.length * 5 / 60).ceil();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validate emails?'),
        content: Text(
          'These ${batch.length} businesses have no website, so each one is looked up on the '
          'web by name, address and phone (roughly $minutes-$maxMinutes min). An address is kept '
          'only if the page it appears on also shows the business\'s phone number, and it must '
          'pass a deliverability check. Expect many to come back empty. Nothing is sent to anyone.'
          '${pending.length > batch.length ? '\n\nThis run covers the first ${batch.length} of ${pending.length}; run it again for the rest.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Validate')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await _repo.validateWebsiteLeadEmails([for (final l in batch) l.dbId!]);
    } catch (e) {
      if (!mounted) return;
      _toast(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    setState(() {
      _running = true;
      _snapshot = null;
      _lastRun = null;
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
      setState(() {
        _running = false;
        _lastRun = snap;
      });
      widget.onFinished();
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _running = false);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cancel() async {
    try {
      await _repo.cancelEmailValidation();
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running) return _progress(context);

    final pending = _pending.length;
    final lastRun = _lastRun;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.neutral200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        const Text(
                          'Find contact emails',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pending == 0
                              ? 'Every lead in this list already has an email.'
                              : '$pending without an email · $_withEmail with one. '
                                  'Looked up on the web by name and phone — partial coverage.',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Wraps under the text so it still fits on a phone-width window.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (_withEmail > 0 && widget.onEmailOnlyChanged != null)
                    FilterChip(
                      label: Text('Has email ($_withEmail)'),
                      selected: widget.emailOnly,
                      onSelected: widget.onEmailOnlyChanged,
                    ),
                  FilledButton.icon(
                    onPressed: pending == 0 ? null : _start,
                    icon: const Icon(AppIcons.mail, size: 16),
                    label: const Text('Validate emails'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (lastRun != null && lastRun.hasJob) ...[
          const SizedBox(height: 10),
          EmailOutcomeSummary(snapshot: lastRun),
          if (lastRun.stoppedReason != null && lastRun.stoppedReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              lastRun.stoppedReason!,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.accent700, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ],
    );
  }

  Widget _progress(BuildContext context) {
    final snap = _snapshot;
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
                      ? 'Starting email search…'
                      : 'Searching — ${snap.checked}/${snap.total} checked · ${snap.validCount} found'
                          '${snap.noEmailCount > 0 ? ' · ${snap.noEmailCount} none' : ''}'
                          '${snap.errorCount > 0 ? ' · ${snap.errorCount} errors' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.subtle),
                ),
              ),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
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
              'Looking up ${snap!.currentLeadBusiness}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.faint),
            ),
          ],
        ],
      ),
    );
  }
}
