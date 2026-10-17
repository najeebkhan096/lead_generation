import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/validation_start.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';

const _pollInterval = Duration(seconds: 2);

/// A run is capped by the backend; longer lists are validated in chunks.
const leadValidationBatch = 500;

/// Checks each lead's phone number against the linked WhatsApp Web session.
/// Verified numbers land in the WhatsApp leads collection.
///
/// Works on [leads], the list as the page currently filters it, and skips
/// numbers that were already checked. [onFinished] fires when a run ends so
/// the page can reload and show the results.
class LeadValidationBar extends StatefulWidget {
  const LeadValidationBar({
    super.key,
    required this.collection,
    required this.leads,
    required this.onFinished,
    this.filters = const [],
  });

  /// The backend collection [leads] came from (`leads`).
  final String collection;
  final List<Lead> leads;
  final VoidCallback onFinished;

  /// Page-specific filter chips shown beside the action.
  final List<Widget> filters;

  @override
  State<LeadValidationBar> createState() => _LeadValidationBarState();
}

class _LeadValidationBarState extends State<LeadValidationBar> {
  Timer? _timer;
  bool _running = false;
  WhatsAppValidationSnapshot? _snapshot;

  // Last finished run, kept until the next one starts.
  WhatsAppValidationSnapshot? _last;

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

  /// Numbers that already have a definite answer (on WhatsApp or not).
  List<Lead> get _waChecked =>
      widget.leads.where((l) => l.dbId != null && _hasText(l.phone) && l.whatsAppCheckedAt != null).toList();

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Confirms a run. When [recheckCount] > 0 it also offers to include the
  /// leads that were already answered; returns `null` if cancelled, else
  /// whether to re-check them.
  Future<bool?> _confirmRun({
    required String title,
    required String message,
    required int recheckCount,
    required String recheckLabel,
    bool recheckByDefault = false,
  }) {
    var recheck = recheckByDefault;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (recheckCount > 0) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: recheck,
                  onChanged: (v) => setLocal(() => recheck = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(recheckLabel),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, recheck), child: const Text('Validate')),
          ],
        ),
      ),
    );
  }

  /// A run was refused because everything selected was already checked.
  /// Offers the explicit override instead of leaving the user stuck.
  Future<bool> _offerRecheck(String message) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already checked'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Re-check anyway')),
        ],
      ),
    );
    return go == true;
  }

  void _noteStart(ValidationStart start) {
    final summary = start.summary;
    if (summary != null && mounted) _toast(summary);
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
    final checked = _waChecked;
    if (pending.isEmpty && checked.isEmpty) {
      _toast('Nothing to check — none of these leads has a phone number.');
      return;
    }
    final decision = await _confirmRun(
      title: 'Validate WhatsApp numbers?',
      message: pending.isEmpty
          ? 'Every number here was already checked.'
          : 'Checks ${pending.take(leadValidationBatch).length} number${pending.length == 1 ? '' : 's'} against your '
              'connected WhatsApp Web session (roughly ${(pending.take(leadValidationBatch).length * 5 / 60).ceil()}-'
              '${(pending.take(leadValidationBatch).length * 7 / 60).ceil()} min). Numbers already checked are skipped. '
              'It only looks up whether each number is on WhatsApp — no messages are sent.'
              '${pending.length > leadValidationBatch ? '\n\nThis run covers the first $leadValidationBatch of ${pending.length}; run it again for the rest.' : ''}',
      recheckCount: checked.length,
      recheckLabel: 'Also re-ask ${checked.length} number${checked.length == 1 ? '' : 's'} already checked',
      recheckByDefault: pending.isEmpty,
    );
    if (decision == null || !mounted) return;
    final pool = decision ? [...pending, ...checked] : pending;
    await _runWhatsApp([for (final l in pool.take(leadValidationBatch)) l.dbId!], recheck: decision);
  }

  Future<void> _runWhatsApp(List<String> ids, {required bool recheck}) async {
    try {
      final start = await _repo.validateSavedLeadWhatsApp(widget.collection, ids, recheck: recheck);
      _noteStart(start);
    } on AlreadyCheckedException catch (e) {
      if (mounted && await _offerRecheck(e.message)) await _runWhatsApp(ids, recheck: true);
      return;
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    _begin();
  }

  void _begin() {
    setState(() {
      _running = true;
      _snapshot = null;
      _last = null;
    });
    _poll();
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!_running) return;
    try {
      final snap = await _repo.getWhatsAppValidationStatus();
      if (!mounted) return;
      setState(() => _snapshot = snap);
      if (snap.status == 'running') return;

      _timer?.cancel();
      setState(() {
        _last = _snapshot;
        _running = false;
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
      await _repo.cancelWhatsAppValidation();
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_running) return _progress();

    final waPending = _waPending.length;
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
                              : 'WhatsApp: $waPending to check · of $total loaded',
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
                  FilledButton.icon(
                    onPressed: waPending == 0 && _waChecked.isEmpty ? null : _startWhatsApp,
                    icon: const Icon(AppIcons.chat, size: 16),
                    label: const Text('WhatsApp'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_last != null) ...[
          const SizedBox(height: 10),
          _summary(_last!),
        ],
      ],
    );
  }

  Widget _summary(WhatsAppValidationSnapshot snap) {
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
            if (snap.reusedCount > 0)
              chip('already verified', snap.reusedCount, AppTheme.sage100, AppTheme.sage800),
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
    final total = _snapshot?.total ?? 0;
    final checked = _snapshot?.checked ?? 0;
    final found = _snapshot?.validCount ?? 0;
    final started = _snapshot != null;
    final current = _snapshot?.currentLeadBusiness;

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
                      ? 'Starting WhatsApp validation…'
                      : 'WhatsApp — $checked/$total checked · $found on WhatsApp',
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
