import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/email_validation_snapshot.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import 'email_outcome_summary.dart';

const _pollInterval = Duration(seconds: 2);

/// A run is capped by the backend; longer lists are validated in chunks.
const leadValidationBatch = 500;

enum _Kind { whatsapp, email }

/// The two ways a lead is validated, as one control shared by every lead
/// list — review leads (`leads`) and no-website leads (`websiteLeads`):
///
///  * **WhatsApp** — checks each phone number against the linked WhatsApp
///    Web session. Verified numbers land in the WhatsApp leads collection.
///  * **Email** — finds and verifies a contact email (crawls the lead's
///    site if it has one, otherwise looks the business up on the web).
///    Verified addresses land in the Email leads collection.
///
/// Works on [leads], the list as the page currently filters it, and skips
/// leads that were already validated that way. [onFinished] fires when a
/// run ends so the page can reload and show the results.
class LeadValidationBar extends StatefulWidget {
  const LeadValidationBar({
    super.key,
    required this.collection,
    required this.leads,
    required this.onFinished,
    this.filters = const [],
  });

  /// `leads` or `websiteLeads` — which backend collection [leads] came from.
  final String collection;
  final List<Lead> leads;
  final VoidCallback onFinished;

  /// Page-specific filter chips shown beside the actions.
  final List<Widget> filters;

  @override
  State<LeadValidationBar> createState() => _LeadValidationBarState();
}

class _LeadValidationBarState extends State<LeadValidationBar> {
  Timer? _timer;
  _Kind? _running;
  WhatsAppValidationSnapshot? _waSnapshot;
  EmailValidationSnapshot? _emailSnapshot;

  // Last finished run, kept until the next one starts.
  _Kind? _lastKind;
  WhatsAppValidationSnapshot? _lastWa;
  EmailValidationSnapshot? _lastEmail;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _hasText(String? v) => v != null && v.trim().isNotEmpty;

  /// Never-checked leads with a phone — `whatsAppCheckedAt == null` is what
  /// separates "never checked" from "checked, not on WhatsApp".
  List<Lead> get _waPending =>
      widget.leads.where((l) => l.dbId != null && _hasText(l.phone) && l.whatsAppCheckedAt == null).toList();

  List<Lead> get _emailPending => widget.leads.where((l) => l.dbId != null && !_hasText(l.email)).toList();

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startWhatsApp() async {
    final WhatsAppWebStatus status;
    try {
      status = await _repo.getWhatsAppWebStatus();
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;

    if (!status.isReady) {
      final connect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp Web not connected'),
          content: const Text(
            'Checking numbers needs a linked WhatsApp Web session. '
            'Connect it from the WhatsApp tool, then come back here.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Go connect')),
          ],
        ),
      );
      if (connect == true && mounted) context.go('/whatsapp');
      return;
    }

    final blocked = status.safety.blockedReason;
    if (blocked != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp checks paused'),
          content: Text(
            '$blocked\n\nThis keeps the linked WhatsApp account from being flagged for '
            'automated-looking activity — it resets on its own.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final pending = _waPending;
    if (pending.isEmpty) {
      _toast('Nothing to check — every lead here is already checked or has no phone number.');
      return;
    }
    final batch = pending.take(leadValidationBatch).toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validate WhatsApp numbers?'),
        content: Text(
          'Checks ${batch.length} number${batch.length == 1 ? '' : 's'} against your connected '
          'WhatsApp Web session (roughly ${(batch.length * 5 / 60).ceil()}-${(batch.length * 7 / 60).ceil()} min). '
          'It only looks up whether each number is on WhatsApp — no messages are sent.'
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
      await _repo.validateSavedLeadWhatsApp(widget.collection, [for (final l in batch) l.dbId!]);
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    _begin(_Kind.whatsapp);
  }

  Future<void> _startEmail() async {
    final pending = _emailPending;
    if (pending.isEmpty) {
      _toast('Every lead here already has an email.');
      return;
    }
    final batch = pending.take(leadValidationBatch).toList();
    final withSite = batch.where((l) => _hasText(l.website)).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validate emails?'),
        content: Text(
          'Looks for a contact email for ${batch.length} business${batch.length == 1 ? '' : 'es'}: '
          '$withSite by reading their website, ${batch.length - withSite} by searching the web for '
          'their name and phone (roughly ${(batch.length * 2.5 / 60).ceil()}-${(batch.length * 5 / 60).ceil()} min). '
          'Only addresses that pass a deliverability check are kept — expect some to come back '
          'empty. Nothing is sent to anyone.'
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
      await _repo.validateSavedLeadEmails(widget.collection, [for (final l in batch) l.dbId!]);
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    _begin(_Kind.email);
  }

  void _begin(_Kind kind) {
    setState(() {
      _running = kind;
      _waSnapshot = null;
      _emailSnapshot = null;
      _lastKind = null;
      _lastWa = null;
      _lastEmail = null;
    });
    _poll();
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final kind = _running;
    if (kind == null) return;
    try {
      final bool running;
      if (kind == _Kind.whatsapp) {
        final snap = await _repo.getWhatsAppValidationStatus();
        if (!mounted) return;
        setState(() => _waSnapshot = snap);
        running = snap.status == 'running';
      } else {
        final snap = await _repo.getEmailValidationStatus();
        if (!mounted) return;
        setState(() => _emailSnapshot = snap);
        running = snap.status == 'running';
      }
      if (running) return;

      _timer?.cancel();
      setState(() {
        _lastKind = kind;
        _lastWa = _waSnapshot;
        _lastEmail = _emailSnapshot;
        _running = null;
      });
      widget.onFinished();
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _running = null);
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cancel() async {
    try {
      if (_running == _Kind.whatsapp) {
        await _repo.cancelWhatsAppValidation();
      } else {
        await _repo.cancelEmailValidation();
      }
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running != null) return _progress();

    final waPending = _waPending.length;
    final emailPending = _emailPending.length;
    final total = widget.leads.length;

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
                    child: const Icon(AppIcons.shieldCheck, size: 17, color: AppTheme.sage700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Validate these leads',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          total == 0
                              ? 'Nothing to validate in this list.'
                              : '$waPending of $total not yet checked on WhatsApp · '
                                  '$emailPending of $total without a verified email',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.faint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Wraps under the text so it still fits a phone-width window.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  ...widget.filters,
                  OutlinedButton.icon(
                    onPressed: waPending == 0 ? null : _startWhatsApp,
                    icon: const Icon(AppIcons.chat, size: 16),
                    label: const Text('WhatsApp'),
                  ),
                  FilledButton.icon(
                    onPressed: emailPending == 0 ? null : _startEmail,
                    icon: const Icon(AppIcons.mail, size: 16),
                    label: const Text('Email'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_lastKind != null) ...[
          const SizedBox(height: 10),
          _summary(),
        ],
      ],
    );
  }

  Widget _summary() {
    if (_lastKind == _Kind.email && _lastEmail != null) {
      final snap = _lastEmail!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmailOutcomeSummary(snapshot: snap),
          if (snap.stoppedReason != null && snap.stoppedReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              snap.stoppedReason!,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.accent700, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      );
    }
    final snap = _lastWa;
    if (snap == null) return const SizedBox.shrink();

    Widget chip(String label, int count, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
          child: Text('$count $label', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('on WhatsApp', snap.validCount, AppTheme.sage100, AppTheme.sage800),
            chip('not on WhatsApp', snap.invalidCount, AppTheme.neutral100, AppTheme.neutral700),
            if (snap.errorCount > 0) chip('errors', snap.errorCount, AppTheme.accent100, AppTheme.accent800),
          ],
        ),
        if (snap.stoppedReason != null && snap.stoppedReason!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            snap.stoppedReason!,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.accent700, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  Widget _progress() {
    final isWa = _running == _Kind.whatsapp;
    final int total = isWa ? (_waSnapshot?.total ?? 0) : (_emailSnapshot?.total ?? 0);
    final int checked = isWa ? (_waSnapshot?.checked ?? 0) : (_emailSnapshot?.checked ?? 0);
    final int found = isWa ? (_waSnapshot?.validCount ?? 0) : (_emailSnapshot?.validCount ?? 0);
    final started = isWa ? _waSnapshot != null : _emailSnapshot != null;
    final current = isWa ? _waSnapshot?.currentLeadBusiness : _emailSnapshot?.currentLeadBusiness;

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
                  !started
                      ? (isWa ? 'Starting WhatsApp validation…' : 'Starting email validation…')
                      : '${isWa ? 'WhatsApp' : 'Email'} — $checked/$total checked · '
                          '$found ${isWa ? 'on WhatsApp' : 'verified'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.subtle),
                ),
              ),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: LinearProgressIndicator(value: total > 0 ? checked / total : 0.0, minHeight: 6),
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            Text(
              'Checking $current',
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
