import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/business_categories.dart';
import '../../domain/entities/coverage_option.dart';
import '../../domain/entities/maps_session_status.dart';
import '../../domain/entities/scan_run.dart';
import '../../domain/repositories/lead_repository.dart';
import '../design_system/design_system.dart';
import '../widgets/google_session_card.dart';
import '../utils/date_format.dart';
import '../widgets/scan_layout.dart';
import '../../domain/entities/state_city_scan_snapshot.dart';

/// Configures and starts a scan — for each category (one at a time),
/// every US state is scanned in order, and within the active state, up to
/// `concurrency` cities are scraped at once. Nothing is written to
/// Firestore; each category's results are packaged into one .xlsx
/// workbook (one sheet per state), checkpointed to Firebase Storage the
/// instant each state finishes — see [StateScanPage] for the live
/// state-by-state, city-by-city progress view, and the Excel Archive page
/// for browsing everything saved this way.
class ExcelScanPage extends StatefulWidget {
  const ExcelScanPage({super.key, this.type});

  /// Preselects the scan type: `no-website`, anything else = 1-star reviews.
  final String? type;

  @override
  State<ExcelScanPage> createState() => _ExcelScanPageState();
}

class _ExcelScanPageState extends State<ExcelScanPage> {
  final _categoryController = TextEditingController();
  final List<String> _targetServices = [];

  /// What this scan looks for: 1-star reviews (needs a time range) or businesses with no website.
  late bool _noWebsite = widget.type == 'no-website';

  String _dateRange = '30';
  int _concurrency = 10;
  String _coverage = 'extended';
  List<CoverageOption> _coverageOptions = const [];
  bool _starting = false;

  /// No-website scans that were stopped or cut off and can be resumed.
  List<ScanRun> _runs = const [];

  /// This page stays mounted while you use the rest of the app, so the list
  /// refreshes itself: a scan stopped (or cut off) a moment ago appears without a reload.
  Timer? _runsTimer;
  String? _busyRun;
  StateCityScanSnapshot? _existingJob;
  MapsSessionStatus? _session;

  static const _dateRanges = <String, String>{
    '7': 'Last 7 days',
    '14': 'Last 14 days',
    '21': 'Last 21 days',
    '22': 'Last 22 days',
    '23': 'Last 23 days',
    '28': 'Last 28 days',
    '30': 'Last 30 days',
  };

  @override
  void initState() {
    super.initState();
    _checkExistingJob();
    _loadCoverage();
    _loadRuns();
    _runsTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_noWebsite && !_starting) _loadRuns();
    });
  }

  Future<void> _loadRuns() async {
    try {
      final runs = await context.read<LeadRepository>().listNoWebsiteRuns();
      if (mounted) setState(() => _runs = runs);
    } catch (_) {
      // Best-effort: the form works without the list.
    }
  }

  Future<void> _resumeRun(ScanRun run) async {
    setState(() => _busyRun = run.id);
    try {
      await context.read<LeadRepository>().resumeNoWebsiteRun(run.id);
      if (!mounted) return;
      context.pushReplacement('/scan-progress');
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      if (message.toLowerCase().contains('already running')) {
        context.push('/scan-progress');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 8)));
      }
    } finally {
      if (mounted) setState(() => _busyRun = null);
    }
  }

  Future<void> _discardRun(ScanRun run) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Discard this scan?',
      message: 'Its saved progress is forgotten, so it can no longer be resumed. '
          'The ${run.leads} no-website lead${run.leads == 1 ? '' : 's'} already found stay in No Website Leads.',
      confirmLabel: 'Discard',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyRun = run.id);
    try {
      await context.read<LeadRepository>().discardNoWebsiteRun(run.id);
      await _loadRuns();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busyRun = null);
    }
  }

  Future<void> _loadCoverage() async {
    try {
      final options = await context.read<LeadRepository>().getScanCoverage();
      if (mounted) setState(() => _coverageOptions = options);
    } catch (_) {
      // The tiers still work without the size estimates.
    }
  }

  // Detects a scan already running on the backend (started earlier, or
  // from another tab/device) so the form can surface a direct link to its
  // live progress up front, instead of only telling the user after they
  // fill in the form and hit "Start" only to be rejected.
  Future<void> _checkExistingJob() async {
    try {
      final snap = await context.read<LeadRepository>().getStateScanStatus();
      if (!mounted) return;
      if (snap.hasJob && snap.status == 'running') setState(() => _existingJob = snap);
    } catch (_) {
      // Best-effort only — the form still works even if this check fails.
    }
  }

  @override
  void didUpdateWidget(ExcelScanPage old) {
    super.didUpdateWidget(old);
    // The sidebar's two scan entries open this same page with a different type.
    if (old.type != widget.type && !_starting) setState(() => _noWebsite = widget.type == 'no-website');
  }

  @override
  void dispose() {
    _runsTimer?.cancel();
    _categoryController.dispose();
    super.dispose();
  }

  void _addService([String? service]) {
    final s = (service ?? _categoryController.text).trim();
    if (s.isEmpty) return;
    if (!_targetServices.contains(s)) {
      setState(() {
        _targetServices.add(s);
        _categoryController.clear();
      });
    }
  }

  void _removeService(String service) {
    setState(() => _targetServices.remove(service));
  }

  Future<void> _submit() async {
    if (_targetServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one service to start scanning')),
      );
      return;
    }

    if (!_noWebsite && googleSessionBlocksScan(_session)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to Google first (the card above). Without it, 1-star reviews would be missed.')),
      );
      return;
    }

    setState(() => _starting = true);
    try {
      await context.read<LeadRepository>().startStateScan(
            categories: List.from(_targetServices),
            concurrency: _concurrency,
            dateRange: _dateRange,
            coverage: _coverage,
            mode: _noWebsite ? 'no_website' : 'reviews',
          );
      if (!mounted) return;
      context.pushReplacement('/scan-progress');
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      // A scan is already active on the backend (e.g. started earlier, or
      // from another tab) — nothing new was started, so send the user
      // straight to the live dashboard for it instead of leaving them
      // stuck on a form that just rejected their input.
      if (message.toLowerCase().contains('already running')) {
        context.push('/scan-progress');
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 8)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String get _dateLabel => _dateRanges[_dateRange] ?? '$_dateRange days';

  String get _coverageLabel => switch (_coverage) {
        'standard' => 'Standard',
        'maximum' => 'Maximum',
        _ => 'Extended',
      };

  @override
  Widget build(BuildContext context) {
    // Only the 1-star scan reads reviews, so only it needs Google signed in.
    final blocked = !_noWebsite && googleSessionBlocksScan(_session);
    return AppPage(
      title: 'New scan',
      subtitle: _noWebsite
          ? 'Find businesses with no website on Google Maps in every US state.'
          : 'Find businesses with recent 1-star reviews in every US state.',
      children: [
        if (_existingJob != null)
          AppAlert(
            tone: AppTone.primary,
            icon: AppIcons.zap,
            message: 'A scan is already running'
                '${_existingJob!.currentCategory != null ? ' ("${_existingJob!.currentCategory}")' : ''}.',
            actions: [
              AppButton.primary(label: 'View live progress', size: AppButtonSize.sm, onPressed: () => context.push('/scan-progress')),
            ],
          ),
        if (_noWebsite && _runs.isNotEmpty)
          _UnfinishedScans(
            runs: _runs,
            busyId: _busyRun,
            disabled: _starting || _existingJob != null,
            onResume: _resumeRun,
            onDiscard: _discardRun,
          ),
        if (!_noWebsite)
          GoogleSessionCard(
            onStatus: (s) {
              if (mounted) setState(() => _session = s);
            },
          ),
        ScanLayout(
          sections: [
            SectionCard(
              title: 'What are you looking for?',
              subtitle: 'Each scan type finds a different kind of lead',
              child: _ScanTypePicker(noWebsite: _noWebsite, enabled: !_starting, onChanged: (v) {
                setState(() => _noWebsite = v);
                if (v) _loadRuns();
              }),
            ),
            SectionCard(
              title: 'Target',
              subtitle: 'Where to look and which businesses to look for',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldShell(
                    label: 'Country',
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.neutral100,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Icon(AppIcons.globe, size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 8),
                          Text('United States', style: AppText.cell.copyWith(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('All 50 states + D.C.', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  FieldShell(
                    label: 'Business categories',
                    helper: _noWebsite ? 'Each category is scanned one at a time.' : 'Each category is scanned one at a time and saved as its own Excel workbook.',
                    child: _categoryField(),
                  ),
                  if (_targetServices.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.md),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final s in _targetServices)
                          InputChip(
                            label: Text(s),
                            deleteIcon: const Icon(AppIcons.close, size: 14),
                            onDeleted: _starting ? null : () => _removeService(s),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SectionCard(
              title: 'Coverage',
              subtitle: 'How many places each state is searched',
              child: _CoveragePicker(
                options: _coverageOptions,
                selected: _coverage,
                enabled: !_starting,
                onSelected: (tier) => setState(() => _coverage = tier),
              ),
            ),
            SectionCard(
              title: 'Options',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_noWebsite) ...[
                    AppDropdown<String>(
                      label: 'Date range',
                      helper: 'Only 1-star reviews inside this window are collected.',
                      leadingIcon: AppIcons.calendar,
                      value: _dateRange,
                      options: [for (final e in _dateRanges.entries) AppOption(e.key, e.value)],
                      onChanged: _starting ? null : (v) => setState(() => _dateRange = v),
                    ),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  FieldShell(
                    label: 'Parallel workers',
                    helper: 'How fast pages are opened is set by a shared pace that tunes itself to what Google tolerates, '
                        'so more workers cannot out-run it. 10 keeps it fully fed.',
                    child: Row(
                      children: [
                        Icon(AppIcons.users, size: 16, color: AppTheme.textMuted),
                        Expanded(
                          child: Slider(
                            value: _concurrency.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '$_concurrency workers',
                            onChanged: _starting ? null : (v) => setState(() => _concurrency = v.round()),
                          ),
                        ),
                        SizedBox(width: 84, child: Text('$_concurrency workers', textAlign: TextAlign.end, style: AppText.cell.copyWith(fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          summary: SectionCard(
            title: 'Summary',
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SummaryRow(icon: AppIcons.search, label: 'Looking for', value: _noWebsite ? 'No website' : '1-star reviews'),
                const SummaryRow(icon: AppIcons.globe, label: 'Country', value: 'United States'),
                SummaryRow(
                  icon: AppIcons.tag,
                  label: 'Categories',
                  value: _targetServices.isEmpty ? 'None yet' : (_targetServices.length <= 2 ? _targetServices.join(', ') : '${_targetServices.length} selected'),
                ),
                SummaryRow(icon: AppIcons.mapPin, label: 'Coverage', value: _coverageLabel),
                if (!_noWebsite) SummaryRow(icon: AppIcons.calendar, label: 'Date range', value: _dateLabel),
                SummaryRow(icon: AppIcons.users, label: 'Workers', value: '$_concurrency'),
                const SizedBox(height: AppSpace.md),
                AppAlert(
                  tone: AppTone.success,
                  icon: _noWebsite ? AppIcons.globe : AppIcons.download,
                  message: _noWebsite
                      ? 'Saved to No Website Leads. A business is saved only when its Maps listing is confirmed to have no website; no reviews are read.'
                      : 'Excel-only mode — businesses will not appear in the Leads page or WhatsApp checker.',
                ),
                const SizedBox(height: AppSpace.lg),
                AppButton.primary(
                  label: blocked ? 'Sign in to Google to start' : (_noWebsite ? 'Start no-website scan' : 'Start 1-star scan'),
                  icon: blocked ? null : AppIcons.play,
                  loading: _starting,
                  fullWidth: true,
                  onPressed: _starting || blocked ? null : _submit,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  _noWebsite
                      ? 'Scans every state one at a time; within a state, cities are read in parallel. Re-running it only adds new businesses.'
                      : 'Scans every state one at a time; within a state, cities are read in parallel. Re-scan from the Archive after a month.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryField() {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
        return BusinessCategories.top100.where((o) => o.toLowerCase().contains(textEditingValue.text.toLowerCase()));
      },
      onSelected: _addService,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(hintText: 'Select or type a category…', prefixIcon: Icon(AppIcons.search, size: 17)),
                  enabled: !_starting,
                  onFieldSubmitted: (v) {
                    _addService(v);
                    controller.clear();
                  },
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            AppButton.outlined(
              label: 'Add',
              icon: AppIcons.plus,
              onPressed: _starting
                  ? null
                  : () {
                      _addService(controller.text);
                      controller.clear();
                    },
            ),
          ],
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: AppTheme.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              side: BorderSide(color: AppTheme.border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 480),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(option, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary)),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Standard / Extended / Maximum: how many places the scan searches, and what
/// that means in businesses and hours. A bigger tier finds more leads and takes
/// longer; the scan paces itself to what Google tolerates, so the hours are an
/// estimate of an unbroken run.
class _CoveragePicker extends StatelessWidget {
  const _CoveragePicker({required this.options, required this.selected, required this.enabled, required this.onSelected});

  final List<CoverageOption> options;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onSelected;

  static const _blurb = {
    'standard': 'The 10 largest cities in every state.',
    'extended': 'Every city and town of 25,000+ people. The most leads per hour.',
    'maximum': 'Every place of 5,000+ people, plus a grid of search points across large cities, which Google caps at ~120 results per search.',
  };

  String _duration(double hours) {
    if (hours < 1) return 'under an hour';
    if (hours < 48) return 'about ${hours.round()} hours';
    return 'about ${(hours / 24).toStringAsFixed(1)} days';
  }

  @override
  Widget build(BuildContext context) {
    final tiers = options.isNotEmpty
        ? options
        : const [
            CoverageOption(tier: 'standard', label: 'Standard', searches: 501, businesses: 0, hours: 0),
            CoverageOption(tier: 'extended', label: 'Extended', searches: 0, businesses: 0, hours: 0),
            CoverageOption(tier: 'maximum', label: 'Maximum', searches: 0, businesses: 0, hours: 0),
          ];
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        for (final o in tiers)
          Padding(
            padding: EdgeInsets.only(bottom: o == tiers.last ? 0 : AppSpace.sm + 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: enabled ? () => onSelected(o.tier) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.all(AppSpace.md + 2),
                decoration: BoxDecoration(
                  color: o.tier == selected ? AppTheme.primary100 : AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: o.tier == selected ? AppTheme.primary500 : AppTheme.border, width: o.tier == selected ? 1.6 : 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(o.tier == selected ? AppIcons.checkCircle : AppIcons.mapPin, size: 18, color: o.tier == selected ? AppTheme.primary : AppTheme.textMuted),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(o.label, style: text.titleSmall),
                              if (o.tier == 'extended') ...[const SizedBox(width: 8), const AppBadge('Recommended', tone: AppTone.primary, dense: true)],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(_blurb[o.tier] ?? '', style: text.bodyMedium),
                          if (o.searches > 0 && o.hours > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${o.searches} searches · ~${o.businesses} businesses to read · ${_duration(o.hours)}',
                              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The first choice on the page: which kind of lead this scan finds.
class _ScanTypePicker extends StatelessWidget {
  const _ScanTypePicker({required this.noWebsite, required this.enabled, required this.onChanged});

  final bool noWebsite;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget option({
      required bool selected,
      required IconData icon,
      required String title,
      required String body,
      required List<String> facts,
      required VoidCallback onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary100 : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: selected ? AppTheme.primary500 : AppTheme.border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconTile(icon, tone: selected ? AppTone.primary : AppTone.neutral, size: 34),
                  const SizedBox(width: AppSpace.md),
                  Expanded(child: Text(title, style: text.titleMedium)),
                  Icon(selected ? AppIcons.checkCircle : AppIcons.chevronRight, size: 18, color: selected ? AppTheme.primary : AppTheme.textMuted),
                ],
              ),
              const SizedBox(height: AppSpace.sm + 2),
              Text(body, style: text.bodyMedium),
              const SizedBox(height: AppSpace.md),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final f in facts) AppBadge(f, tone: selected ? AppTone.primary : AppTone.neutral, dense: true)]),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final reviews = option(
          selected: !noWebsite,
          icon: AppIcons.thumbsDown,
          title: '1-star reviews',
          body: 'Businesses that received a recent 1-star review — people unhappy enough to want a better option.',
          facts: const ['Needs a time range', 'Google sign-in required', 'Saved as an Excel archive'],
          onTap: () => onChanged(false),
        );
        final website = option(
          selected: noWebsite,
          icon: AppIcons.globe,
          title: 'No website',
          body: 'Businesses whose Google Maps listing has no website — they need one.',
          facts: const ['No time range', 'No Google sign-in', 'Saved to No Website Leads'],
          onTap: () => onChanged(true),
        );
        if (c.maxWidth < 560) {
          return Column(children: [reviews, const SizedBox(height: AppSpace.md), website]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: reviews), const SizedBox(width: AppSpace.md), Expanded(child: website)],
        );
      },
    );
  }
}

/// No-website scans that were stopped (or cut off by a restart): resume one and
/// only the cities it had not covered are searched.
class _UnfinishedScans extends StatelessWidget {
  const _UnfinishedScans({
    required this.runs,
    required this.busyId,
    required this.disabled,
    required this.onResume,
    required this.onDiscard,
  });

  final List<ScanRun> runs;
  final String? busyId;

  /// Another scan is running, so nothing can be resumed right now.
  final bool disabled;
  final ValueChanged<ScanRun> onResume;
  final ValueChanged<ScanRun> onDiscard;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Unfinished no-website scans',
      subtitle: 'Resume one and the cities it already covered are skipped',
      icon: AppIcons.history,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < runs.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppTheme.divider),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md + 2),
              child: LayoutBuilder(
                builder: (context, c) {
                  final run = runs[i];
                  final info = Row(
                    children: [
                      IconTile(run.interrupted ? AppIcons.alert : AppIcons.pause, tone: run.interrupted ? AppTone.warning : AppTone.neutral, size: 36),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(
                                  run.categories.take(3).join(', ') + (run.categories.length > 3 ? ' +${run.categories.length - 3}' : ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              AppBadge(run.interrupted ? 'Interrupted' : 'Stopped', tone: run.interrupted ? AppTone.warning : AppTone.neutral, dense: true),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              '${run.percent}% done · ${groupedNumber(run.leads)} no-website lead${run.leads == 1 ? '' : 's'} · '
                              '${groupedNumber(run.citiesLeft)} cities left'
                              '${run.updatedAt == null ? '' : ' · ${run.interrupted ? 'cut off' : 'stopped'} ${formatDate(run.updatedAt)}'}',
                              style: text.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            SizedBox(width: 260, child: AppProgressBar(value: run.percent / 100, height: 5)),
                          ],
                        ),
                      ),
                    ],
                  );
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton.primary(
                        label: 'Resume',
                        icon: AppIcons.play,
                        size: AppButtonSize.sm,
                        loading: busyId == run.id,
                        onPressed: disabled || busyId != null ? null : () => onResume(run),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      AppButton.text(label: 'Discard', size: AppButtonSize.sm, onPressed: busyId != null ? null : () => onDiscard(run)),
                    ],
                  );
                  if (c.maxWidth < 560) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: AppSpace.md), actions]);
                  }
                  return Row(children: [Expanded(child: info), const SizedBox(width: AppSpace.lg), actions]);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
