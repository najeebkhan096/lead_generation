import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/email_validation.dart';
import '../../domain/entities/lead_page.dart';
import '../../domain/entities/whatsapp_web_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../design_system/design_system.dart';
import '../../domain/entities/lead.dart';
import '../widgets/state_scope_section.dart' show stateLabelOf;
import '../widgets/state_validation_list.dart';

const _pollInterval = Duration(seconds: 2);

/// The no-website leads, validated one search at a time — first pick the search
/// (a category such as "Cafe USA"), then the states of its leads to validate.
/// One tab per way to qualify them:
///
///  * **WhatsApp** — checks each lead's phone number against the linked
///    WhatsApp Web session and flags the ones that are on WhatsApp.
///  * **Email** — looks each business up on the public web for a business email
///    address and keeps the ones that verify as deliverable.
///
/// Both tabs list that search's states, with how far each is validated, and let
/// you run the selected states, a single state, or all of them.
class NoWebsiteValidationPage extends StatefulWidget {
  const NoWebsiteValidationPage({super.key, this.initialTab = 0});

  /// 0 = WhatsApp, 1 = Email.
  final int initialTab;

  @override
  State<NoWebsiteValidationPage> createState() => _NoWebsiteValidationPageState();
}

class _NoWebsiteValidationPageState extends State<NoWebsiteValidationPage> {
  List<LeadCategory>? _categories;
  String? _categoriesError;
  String? _category;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesError = null);
    try {
      final list = await context.read<LeadRepository>().getLeadCategories(LeadCollection.websiteLeads);
      if (!mounted) return;
      setState(() {
        _categories = list;
        // The one search there is needs no choosing.
        if (list.length == 1) _category = list.first.name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _categoriesError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Widget _picker(BuildContext context) {
    final categories = _categories;
    final text = Theme.of(context).textTheme;
    if (_categoriesError != null) {
      return AppAlert(
        tone: AppTone.error,
        message: _categoriesError!,
        actions: [AppButton.outlined(label: 'Retry', size: AppButtonSize.sm, onPressed: _loadCategories)],
      );
    }
    if (categories == null) return const LinearProgressIndicator(minHeight: 3);
    if (categories.isEmpty) {
      return Text('No no-website leads yet. Run a No-Website scan and they appear here.', style: text.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDropdown<String?>(
          // A fixed width: the menu is capped at 480, so a full-width field breaks it.
          width: 400,
          label: 'Search',
          hint: 'Select a search to validate',
          leadingIcon: AppIcons.filter,
          value: _category,
          options: [
            for (final c in categories) AppOption<String?>(c.name, c.name, caption: groupedNumber(c.count)),
          ],
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          _category == null
              ? 'Pick the search first — validation runs on one search\'s leads, then by state.'
              : 'Showing the states of "$_category".',
          style: text.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpace.pageGutter(MediaQuery.sizeOf(context).width);
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
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
          child: Column(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(gutter, AppSpace.lg, gutter, 0),
                    child: _picker(context),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ValidationTab(spec: _whatsAppSpec, category: _category),
                    _ValidationTab(spec: _emailSpec, category: _category),
                  ],
                ),
              ),
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
    required this.results,
    required this.resultsTitle,
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

  /// The list of leads this validation has qualified, and what to call it.
  final LeadCollection results;
  final String resultsTitle;

  final Future<UnvalidatedWhatsAppSummary> Function(LeadRepository repo, String category) loadSummary;
  final Future<_Progress> Function(LeadRepository repo) poll;
  final Future<void> Function(LeadRepository repo) cancel;

  /// Starts a run over [states] (null = all) of [category]; returns the server's message.
  final Future<String?> Function(LeadRepository repo, String category, List<String>? states, bool recheck) start;
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
  results: LeadCollection.websiteVerified,
  resultsTitle: 'Validated on WhatsApp',
  loadSummary: (repo, category) => repo.getUnvalidatedWhatsAppSummary(collection: 'websiteLeads', category: category),
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
  start: (repo, category, states, _) =>
      repo.startWhatsAppAutoValidation(states: states, collection: 'websiteLeads', category: category),
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
  results: LeadCollection.websiteWithEmail,
  resultsTitle: 'Emails found',
  loadSummary: (repo, category) => repo.getEmailValidationSummary(category: category),
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
  start: (repo, category, states, recheck) => repo.startEmailValidation(states: states, category: category, recheck: recheck),
);

class _ValidationTab extends StatefulWidget {
  const _ValidationTab({required this.spec, required this.category});

  final _ValidationSpec spec;

  /// The search whose leads are validated; null until one is picked.
  final String? category;

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

  /// Bumped whenever the counts reload, so the validated list below does too.
  int _resultsVersion = 0;

  /// Runs of this kind that stopped before finishing, offered for Resume.
  List<ValidationRun> _unfinished = const [];
  final Set<String> _resuming = {};
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
      _loadUnfinished();
    });
  }

  @override
  void didUpdateWidget(covariant _ValidationTab old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      // A different search has different states: nothing ticked carries over.
      _selected.clear();
      _summary = null;
      _loadSummary();
    }
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
    final category = widget.category;
    if (category == null) {
      setState(() {
        _summary = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _spec.loadSummary(_repo, category);
      // Picked another search while this one loaded: that answer is stale.
      if (!mounted || category != widget.category) return;
      final hadSummary = _summary != null;
      setState(() {
        _summary = summary;
        _loading = false;
        // The list below loads itself the first time (and for a new search); it
        // reloads only when counts that already showed have moved.
        if (hadSummary) _resultsVersion += 1;
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

  Future<void> _loadUnfinished() async {
    try {
      final runs = await _repo.listValidationRuns(collection: 'websiteLeads', kind: _spec.isWhatsApp ? 'whatsapp' : 'email');
      if (mounted) setState(() => _unfinished = runs);
    } catch (_) {
      // The card is a convenience; the states below still resume a scope by hand.
    }
  }

  /// Carries a stopped run on from where it left off.
  Future<void> _resume(ValidationRun run) async {
    if (_resuming.contains(run.id) || _starting || _progress.active) return;
    if (_spec.isWhatsApp && !await _whatsAppGate()) return;
    if (!mounted) return;
    setState(() => _resuming.add(run.id));
    try {
      final message = await _repo.resumeValidationRun(run.id);
      _sawRun = true;
      if (message != null) _toast(message);
      await _pollOnce();
      if (mounted && !_progress.active) _loadSummary();
    } catch (e) {
      _toast(_clean(e));
    } finally {
      if (mounted) {
        setState(() => _resuming.remove(run.id));
        _loadUnfinished();
      }
    }
  }

  Future<void> _discard(ValidationRun run) async {
    try {
      await _repo.discardValidationRun(run.id);
    } catch (e) {
      _toast(_clean(e));
    }
    _loadUnfinished();
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
          _loadUnfinished(); // ...or stopped early, and can be resumed
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
        ? 'every state of "${widget.category}"'
        : states.length == 1
            ? '${states.first} · "${widget.category}"'
            : '${states.length} states of "${widget.category}"';
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
    final category = widget.category;
    if (category == null || _starting || _progress.active) return;
    if (_spec.isWhatsApp && !await _whatsAppGate()) return;
    if (!mounted || !await _confirm(states)) return;

    setState(() => _starting = true);
    try {
      final message = await _spec.start(_repo, category, states, _recheck);
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
            if (!_progress.active) ..._unfinishedCards(),
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
            if (widget.category != null) ...[
              const SizedBox(height: AppSpace.lg),
              _ValidatedLeads(
                key: ValueKey('${_spec.isWhatsApp}/${widget.category}'),
                spec: _spec,
                category: widget.category!,
                states: _selected,
                version: _resultsVersion,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A stopped run: what it was, how far it got, and a way to carry on from there.
  List<Widget> _unfinishedCards() {
    return [
      for (final run in _unfinished) ...[
        AppAlert(
          tone: AppTone.warning,
          title: run.status == 'interrupted' ? 'Interrupted validation' : 'Stopped validation',
          message: [
            if (run.category != null) '"${run.category}"',
            run.states.isEmpty ? 'every state' : run.states.join(', '),
            '${run.checked} of ${run.total} checked',
            if (run.found > 0) '${run.found} ${_spec.foundLabel}',
            if (run.stoppedReason != null && run.stoppedReason!.isNotEmpty)
              run.stoppedReason!
            else if (run.status == 'interrupted')
              'the backend stopped while it was running',
          ].join(' · '),
          actions: [
            AppButton.primary(
              label: 'Resume',
              icon: AppIcons.refresh,
              size: AppButtonSize.sm,
              loading: _resuming.contains(run.id),
              onPressed: () => _resume(run),
            ),
            AppButton.outlined(label: 'Discard', size: AppButtonSize.sm, onPressed: _resuming.contains(run.id) ? null : () => _discard(run)),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
      ],
    ];
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
    if (widget.category == null) {
      return Text('Select a search above to see its states.', style: Theme.of(context).textTheme.bodyMedium);
    }
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
        'No leads in this search.',
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


/// The leads this validation has qualified in the selected search — those on
/// WhatsApp, or those with an email found — newest first, paged. Ticking states
/// above narrows it to them. Reloads when a run finishes.
class _ValidatedLeads extends StatefulWidget {
  const _ValidatedLeads({
    super.key,
    required this.spec,
    required this.category,
    required this.states,
    required this.version,
  });

  final _ValidationSpec spec;
  final String category;
  final Set<String> states;

  /// A new value reloads the list.
  final int version;

  @override
  State<_ValidatedLeads> createState() => _ValidatedLeadsState();
}

class _ValidatedLeadsState extends State<_ValidatedLeads> {
  final List<Lead> _leads = [];
  String? _cursor;
  int? _total;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// Guards against a slow answer for an old search overwriting a newer one.
  int _generation = 0;

  LeadRepository get _repo => context.read<LeadRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant _ValidatedLeads old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getLeadsPage(widget.spec.results, category: widget.category, limit: 50);
      if (!mounted || generation != _generation) return;
      setState(() {
        _leads
          ..clear()
          ..addAll(page.leads);
        _cursor = page.nextCursor;
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _more() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.getLeadsPage(widget.spec.results, cursor: cursor, category: widget.category, limit: 50);
      if (!mounted || generation != _generation) return;
      setState(() {
        _leads.addAll(page.leads);
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = widget.states.isEmpty
        ? _leads
        : [for (final l in _leads) if (widget.states.contains(stateLabelOf(l.location))) l];
    final whatsApp = widget.spec.isWhatsApp;
    final filtered = widget.states.isNotEmpty;
    final count = filtered ? '${shown.length}${_cursor != null ? '+' : ''}' : '${_total ?? _leads.length}${_total == null && _cursor != null ? '+' : ''}';

    return SectionCard(
      title: '${widget.spec.resultsTitle} · $count',
      icon: whatsApp ? AppIcons.shieldCheck : AppIcons.mail,
      subtitle: '"${widget.category}"${filtered ? ' · ${widget.states.length} state${widget.states.length == 1 ? '' : 's'} ticked' : ''}',
      trailing: AppIconButton(icon: AppIcons.refresh, tooltip: 'Refresh', onPressed: _loading ? null : _load),
      child: Builder(builder: (context) {
        if (_loading && _leads.isEmpty) return const LoadingView(label: 'Loading…');
        if (_error != null && _leads.isEmpty) {
          return AppAlert(
            tone: AppTone.error,
            message: _error!,
            actions: [AppButton.outlined(label: 'Retry', size: AppButtonSize.sm, onPressed: _load)],
          );
        }
        if (shown.isEmpty) {
          return Text(
            filtered
                ? 'None of the ticked states have one yet.'
                : whatsApp
                    ? 'No numbers confirmed on WhatsApp in this search yet. Validate some states above.'
                    : 'No emails found in this search yet. Run the lookup above.',
            style: text.bodyMedium,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final lead in shown) _row(context, lead, whatsApp),
            if (_cursor != null) ...[
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton.outlined(label: 'Load more', size: AppButtonSize.sm, loading: _loadingMore, onPressed: _more),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _row(BuildContext context, Lead lead, bool whatsApp) {
    final text = Theme.of(context).textTheme;
    final detail = whatsApp ? (lead.phone ?? '') : (lead.email ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead.business, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [stateLabelOf(lead.location), if (detail.isNotEmpty) detail].join(' · '),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          AppBadge(whatsApp ? 'On WhatsApp' : 'Email found', tone: AppTone.success, dense: true),
        ],
      ),
    );
  }
}
