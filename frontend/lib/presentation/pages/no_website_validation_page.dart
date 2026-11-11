import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../design_system/design_system.dart';
import '../widgets/state_validation_list.dart';

const _pollInterval = Duration(seconds: 2);

/// The no-website leads, validated by state — one tab per way to qualify them:
///
///  * **WhatsApp** — checks each lead's phone number against the linked
///    WhatsApp Web session and flags the ones that are on WhatsApp.
///  * **Email** — looks each business up on the public web for a business email
///    address and keeps the ones that verify as deliverable.
///
/// Both tabs list the states the leads are in, with how far each is validated,
/// and let you run the selected states, a single state, or all of them.
class NoWebsiteValidationPage extends StatelessWidget {
  const NoWebsiteValidationPage({super.key, this.initialTab = 0});

  /// 0 = WhatsApp, 1 = Email.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('No-website validation'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(AppIcons.chat, size: 18), text: 'WhatsApp'),
              Tab(icon: Icon(AppIcons.mail, size: 18), text: 'Email'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _ValidationTab(spec: _whatsAppSpec),
              _ValidationTab(spec: _emailSpec),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a run is at, whichever kind of validation it is.
class _Progress {
  const _Progress({
    this.active = false,
    this.status = 'idle',
    this.total = 0,
    this.checked = 0,
    this.found = 0,
    this.notFound = 0,
    this.errors = 0,
    this.current,
    this.stoppedReason,
  });

  final bool active;
  final String status; // idle | running | done | cancelled
  final int total;
  final int checked;
  final int found;
  final int notFound;
  final int errors;
  final String? current;
  final String? stoppedReason;

  bool get hasRun => status != 'idle';
}

/// What differs between the WhatsApp tab and the Email tab.
class _ValidationSpec {
  const _ValidationSpec({
    required this.isWhatsApp,
    required this.title,
    required this.blurb,
    required this.unit,
    required this.foundLabel,
    required this.missLabel,
    required this.runningLabel,
    required this.loadSummary,
    required this.poll,
    required this.cancel,
    required this.start,
  });

  final bool isWhatsApp;
  final String title;
  final String blurb;

  /// What a check applies to ("number", "business").
  final String unit;
  final String foundLabel;
  final String missLabel;
  final String runningLabel;

  final Future<UnvalidatedWhatsAppSummary> Function(LeadRepository repo) loadSummary;
  final Future<_Progress> Function(LeadRepository repo) poll;
  final Future<void> Function(LeadRepository repo) cancel;

  /// Starts a run over [states] (null = all); returns the server's message.
  final Future<String?> Function(LeadRepository repo, List<String>? states, bool recheck) start;
}

final _whatsAppSpec = _ValidationSpec(
  isWhatsApp: true,
  title: 'WhatsApp validation',
  blurb: 'Checks each no-website lead\'s phone number against your linked WhatsApp Web session and flags the ones that '
      'are on WhatsApp. Numbers already checked are skipped. Nothing is sent — it only looks up whether a number is registered.',
  unit: 'number',
  foundLabel: 'on WhatsApp',
  missLabel: 'not on WhatsApp',
  runningLabel: 'Checking WhatsApp numbers',
  loadSummary: (repo) => repo.getUnvalidatedWhatsAppSummary(collection: 'websiteLeads'),
  poll: (repo) async {
    final s = await repo.getWhatsAppValidationStatus();
    return _Progress(
      active: s.active,
      status: s.status,
      total: s.total,
      checked: s.checked,
      found: s.validCount,
      notFound: s.invalidCount,
      errors: s.errorCount,
      current: s.currentLeadBusiness,
      stoppedReason: s.stoppedReason,
    );
  },
  cancel: (repo) => repo.cancelWhatsAppValidation(),
  start: (repo, states, _) => repo.startWhatsAppAutoValidation(states: states, collection: 'websiteLeads'),
);

final _emailSpec = _ValidationSpec(
  isWhatsApp: false,
  title: 'Email lookup',
  blurb: 'A business with no website has no site to read, so each one is looked up on the public web by name, address and '
      'phone. An address is kept only if a page showing this business\'s details publishes it and it checks out as '
      'deliverable. Coverage is partial by design — a wrong address is worse than none.',
  unit: 'business',
  foundLabel: 'with an email',
  missLabel: 'no email found',
  runningLabel: 'Looking up emails',
  loadSummary: (repo) => repo.getEmailValidationSummary(),
  poll: (repo) async {
    final s = await repo.getEmailValidationStatus();
    return _Progress(
      active: s.active,
      status: s.status,
      total: s.total,
      checked: s.checked,
      found: s.validCount,
      notFound: s.invalidCount + s.noEmailCount,
      errors: s.errorCount,
      current: s.currentBusiness,
      stoppedReason: s.stoppedReason,
    );
  },
  cancel: (repo) => repo.cancelEmailValidation(),
  start: (repo, states, recheck) => repo.startEmailValidation(states: states, recheck: recheck),
);

class _ValidationTab extends StatefulWidget {
  const _ValidationTab({required this.spec});

  final _ValidationSpec spec;

  @override
  State<_ValidationTab> createState() => _ValidationTabState();
}

class _ValidationTabState extends State<_ValidationTab> with AutomaticKeepAliveClientMixin {
  UnvalidatedWhatsAppSummary? _summary;
  bool _loading = true;
  String? _error;

  _Progress _progress = const _Progress();
  Timer? _timer;
  bool _starting = false;
  bool _recheck = false;

  /// A run was started (or seen running) from this page. The server keeps only
  /// the last job, which may be another page's, so an old one isn't shown.
  bool _sawRun = false;
  final Set<String> _selected = {};

  // WhatsApp only: is the linked session ready, and is the account resting?
  WhatsAppWebStatus? _web;

  _ValidationSpec get _spec => widget.spec;
  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSummary();
      _loadWeb();
      _pollOnce();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _spec.loadSummary(_repo);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
        // A state that has nothing left can't stay ticked.
        _selected.removeWhere((name) => !summary.locations.any((l) => l.name == name));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  Future<void> _loadWeb() async {
    if (!_spec.isWhatsApp) return;
    try {
      final web = await _repo.getWhatsAppWebStatus();
      if (mounted) setState(() => _web = web);
    } catch (_) {
      // The start gate re-checks and reports it.
    }
  }

  /// Picks up a run already going (the job lives on the server), and keeps
  /// polling while there is one.
  Future<void> _pollOnce() async {
    try {
      final p = await _spec.poll(_repo);
      if (!mounted) return;
      final wasActive = _progress.active;
      setState(() => _progress = p);
      if (p.active) {
        _sawRun = true;
        _timer ??= Timer.periodic(_pollInterval, (_) => _pollOnce());
      } else {
        _timer?.cancel();
        _timer = null;
        if (wasActive) {
          _loadSummary(); // the run finished: counts moved
          _loadWeb();
        }
      }
    } catch (_) {
      // A blip while polling shouldn't kill the display; the next tick retries.
    }
  }

  /// WhatsApp needs a linked session that isn't resting. Returns whether to go on.
  Future<bool> _whatsAppGate() async {
    final WhatsAppWebStatus status;
    try {
      status = await _repo.getWhatsAppWebStatus();
    } catch (e) {
      _toast(_clean(e));
      return false;
    }
    if (!mounted) return false;
    setState(() => _web = status);

    if (!status.isReady) {
      final connect = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp Web not connected'),
          content: const Text(
            'Checking numbers needs a linked WhatsApp Web session. Connect it from the WhatsApp Connection page, then come back here.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Go connect')),
          ],
        ),
      );
      if (connect == true && mounted) context.go('/whatsapp');
      return false;
    }

    final blocked = status.safety.blockedReason;
    if (blocked != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('WhatsApp checks paused'),
          content: Text(
            '$blocked\n\nThis keeps the linked WhatsApp account from being flagged for automated-looking activity — it resets on its own.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _confirm(List<String>? states) async {
    final scope = states == null
        ? 'every state'
        : states.length == 1
            ? states.first
            : '${states.length} states';
    final String message;
    if (_spec.isWhatsApp) {
      message = 'Checks the phone numbers of the no-website leads in $scope that have not been checked yet, one at a time and at a '
          'safe pace. Nothing is sent to them.';
    } else {
      message = 'Looks up the public email of the no-website businesses in $scope that have none yet. Each lookup takes a few '
          'seconds, so a run covers up to 500 businesses — run it again for the rest. '
          '${_recheck ? 'Businesses with no email found earlier are tried again.' : 'Businesses already looked up are skipped.'}';
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_spec.isWhatsApp ? 'Validate WhatsApp numbers' : 'Look up emails'} in $scope?'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    return go == true;
  }

  Future<void> _start(List<String>? states) async {
    if (_starting || _progress.active) return;
    if (_spec.isWhatsApp && !await _whatsAppGate()) return;
    if (!mounted || !await _confirm(states)) return;

    setState(() => _starting = true);
    try {
      final message = await _spec.start(_repo, states, _recheck);
      _sawRun = true;
      if (message != null) _toast(message);
      await _pollOnce();
      // The server answers 200 without a job when there was nothing to do.
      if (mounted && !_progress.active) _loadSummary();
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await _spec.cancel(_repo);
    } catch (_) {
      // best-effort; the next poll shows where it ended
    }
    await _pollOnce();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = AppSpace.pageGutter(width);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.lg, gutter, AppSpace.xxl),
          children: [
            Text(_spec.blurb, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            ..._notices(),
            if (_progress.active) ...[
              _runningCard(),
              const SizedBox(height: AppSpace.lg),
            ] else if (_sawRun && _progress.hasRun) ...[
              _lastRun(),
              const SizedBox(height: AppSpace.lg),
            ],
            SectionCard(
              title: 'States',
              icon: AppIcons.mapPin,
              subtitle: _summary == null
                  ? 'Grouped by the state in each lead\'s location'
                  : '${_summary!.total} ${_spec.unit}${_summary!.total == 1 ? '' : 's'} left to check',
              trailing: AppIconButton(
                icon: AppIcons.refresh,
                tooltip: 'Refresh',
                onPressed: _loading ? null : _loadSummary,
              ),
              child: _states(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _notices() {
    final web = _web;
    if (!_spec.isWhatsApp || web == null || web.isReady) return const [];
    return [
      AppAlert(
        tone: AppTone.warning,
        title: 'WhatsApp Web is not connected',
        message: 'Link a WhatsApp account first — numbers are checked against that live session.',
        actions: [
          AppButton.outlined(label: 'Open WhatsApp Connection', size: AppButtonSize.sm, onPressed: () => context.go('/whatsapp')),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
    ];
  }

  Widget _states() {
    if (_loading && _summary == null) return const LoadingView(label: 'Counting leads…');
    if (_error != null && _summary == null) {
      return AppAlert(
        tone: AppTone.error,
        message: _error!,
        actions: [AppButton.outlined(label: 'Retry', size: AppButtonSize.sm, onPressed: _loadSummary)],
      );
    }
    final summary = _summary;
    if (summary == null || summary.locations.isEmpty) {
      return Text(
        'No no-website leads yet. Run a No-Website scan and they appear here.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final busy = _starting || _progress.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_spec.isWhatsApp) ...[
          AppCheckboxTile(
            value: _recheck,
            onChanged: busy ? null : (v) => setState(() => _recheck = v),
            label: 'Also retry businesses with no email found earlier',
            caption: 'Lookups that found nothing are remembered, so a second run skips them.',
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        StateValidationList(
          summary: summary,
          selected: _selected,
          enabled: !busy,
          unit: _spec.unit,
          foundLabel: _spec.foundLabel,
          includeChecked: _recheck && !_spec.isWhatsApp,
          onToggle: (name, on) => setState(() => on ? _selected.add(name) : _selected.remove(name)),
          onToggleAll: (on) => setState(() {
            _selected.clear();
            if (on) {
              _selected.addAll(summary.locations
                  .where((l) => (_recheck && !_spec.isWhatsApp) ? l.withPhone > 0 : l.count > 0)
                  .map((l) => l.name));
            }
          }),
          onValidate: _start,
        ),
      ],
    );
  }

  Widget _runningCard() {
    final p = _progress;
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  '${_spec.runningLabel} — ${p.checked}/${p.total} checked · ${p.found} ${_spec.foundLabel}',
                  style: text.titleSmall,
                ),
              ),
              AppButton.text(label: 'Cancel', size: AppButtonSize.sm, onPressed: _cancel),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          AppProgressBar(value: p.total > 0 ? p.checked / p.total : null),
          if (p.current != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text('Checking ${p.current}', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
          ],
          if (!_spec.isWhatsApp)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                'Lookups are paced so the search engine doesn\'t block this connection — a few seconds per business.',
                style: text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _lastRun() {
    final p = _progress;
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.status == 'cancelled' ? 'Last run — stopped' : 'Last run — finished',
            style: text.titleSmall,
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              AppBadge('${p.found} ${_spec.foundLabel}', tone: AppTone.success, icon: AppIcons.checkCircle),
              AppBadge('${p.notFound} ${_spec.missLabel}'),
              if (p.errors > 0) AppBadge('${p.errors} errors', tone: AppTone.warning),
            ],
          ),
          if (p.stoppedReason != null && p.stoppedReason!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(p.stoppedReason!, style: text.bodySmall?.copyWith(color: AppTheme.warning700, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
