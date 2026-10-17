import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/business_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/coverage_option.dart';
import '../../domain/entities/maps_session_status.dart';
import '../../domain/repositories/lead_repository.dart';
import '../widgets/google_session_card.dart';
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
  const ExcelScanPage({super.key});

  @override
  State<ExcelScanPage> createState() => _ExcelScanPageState();
}

class _ExcelScanPageState extends State<ExcelScanPage> {
  final _categoryController = TextEditingController();
  final List<String> _targetServices = [];

  String _dateRange = '365';
  int _concurrency = 10;
  String _coverage = 'extended';
  List<CoverageOption> _coverageOptions = const [];
  bool _starting = false;
  StateCityScanSnapshot? _existingJob;
  MapsSessionStatus? _session;

  static const _dateRanges = <String, String>{
    '7': 'Last 7 days',
    '28': 'Last 28 days',
    '30': 'Last 30 days',
    '90': 'Last 90 days',
    '365': 'Last 365 days',
  };

  @override
  void initState() {
    super.initState();
    _checkExistingJob();
    _loadCoverage();
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
  void dispose() {
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

    if (googleSessionBlocksScan(_session)) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excel Scan')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Scans every US state one at a time — within the active state, cities '
                    'are scraped in parallel across your worker pool. Only 1-star reviews '
                    'inside the date window are collected, and every business is read '
                    'completely: reviews are sorted and read back to the start of the '
                    'window, so none are skipped. Each category becomes one Excel workbook '
                    '(one sheet per state), stamped with the scan date and saved as each '
                    'state finishes. After a month, Re-scan it from the Archive.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  GoogleSessionCard(
                    onStatus: (s) {
                      if (mounted) setState(() => _session = s);
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.sage100,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                    child: Row(
                      children: [
                        const Icon(AppIcons.download, color: AppTheme.sage700, size: 19),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Excel-only mode — businesses will not appear in the Leads page or WhatsApp checker.',
                            style: const TextStyle(color: AppTheme.sage700, fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_existingJob != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.accent100,
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'A scan is already running'
                              '${_existingJob!.currentCategory != null ? ' ("${_existingJob!.currentCategory}")' : ''}.',
                              style: const TextStyle(color: AppTheme.accent700, fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => context.push('/scan-progress'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent700),
                            child: const Text('View live progress'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Country', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.neutral100,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.neutral200),
                    ),
                    child: const Row(
                      children: [
                        Icon(AppIcons.globe, size: 18, color: AppTheme.subtle),
                        SizedBox(width: 10),
                        Text('United States', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink)),
                        Spacer(),
                        Text('All 50 states + D.C.', style: TextStyle(fontSize: 12, color: AppTheme.faint)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Business categories', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 8),
                  Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                      return BusinessCategories.top100
                          .where((o) => o.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                    },
                    onSelected: _addService,
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                hintText: 'Select or type a category…',
                                prefixIcon: Icon(AppIcons.search, size: 19),
                                isDense: true,
                              ),
                              enabled: !_starting,
                              onFieldSubmitted: (v) {
                                _addService(v);
                                controller.clear();
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filled(
                            onPressed: _starting
                                ? null
                                : () {
                                    _addService(controller.text);
                                    controller.clear();
                                  },
                            icon: const Icon(AppIcons.plus, size: 19),
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: AppTheme.surface,
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                        ],
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                          color: AppTheme.surface,
                          child: Container(
                            width: 512,
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                                    child: Text(option),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_targetServices.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _targetServices
                          .map((s) => Chip(
                                label: Text(s),
                                deleteIcon: const Icon(AppIcons.close, size: 14),
                                onDeleted: _starting ? null : () => _removeService(s),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Coverage', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 8),
                  _CoveragePicker(
                    options: _coverageOptions,
                    selected: _coverage,
                    enabled: !_starting,
                    onSelected: (tier) => setState(() => _coverage = tier),
                  ),
                  const SizedBox(height: 20),
                  Text('Date range', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _dateRange,
                    icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                    items: _dateRanges.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: _starting
                        ? null
                        : (v) {
                            if (v != null) setState(() => _dateRange = v);
                          },
                  ),
                  const SizedBox(height: 20),
                  Text('Parallel workers', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radius)),
                    child: Row(
                      children: [
                        const Icon(AppIcons.users, size: 18, color: AppTheme.accent700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Slider(
                            value: _concurrency.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            activeColor: AppTheme.accent500,
                            label: '$_concurrency workers',
                            onChanged: _starting ? null : (v) => setState(() => _concurrency = v.round()),
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text(
                            '$_concurrency workers',
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'How fast pages are opened is set by a shared pace that tunes itself to what Google tolerates '
                    '(it speeds up while things are healthy and backs off at the first sign of trouble). '
                    'Workers only keep that pace fed, so more of them cannot out-run it. 10 keeps it fully fed.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppTheme.faint),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _starting || googleSessionBlocksScan(_session) ? null : _submit,
                    child: _starting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.surface),
                          )
                        : Text(googleSessionBlocksScan(_session) ? 'Sign in to Google to start' : 'Start Excel scan'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    return Column(
      children: [
        for (final o in tiers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: enabled ? () => onSelected(o.tier) : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: o.tier == selected ? AppTheme.accent100 : AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: o.tier == selected ? AppTheme.accent500 : AppTheme.neutral200, width: o.tier == selected ? 1.6 : 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(o.tier == selected ? AppIcons.shieldCheck : AppIcons.mapPin, size: 18, color: AppTheme.accent700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.tier == 'extended' ? '${o.label} (recommended)' : o.label,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(_blurb[o.tier] ?? '', style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppTheme.neutral700)),
                          if (o.searches > 0 && o.hours > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${o.searches} searches · ~${o.businesses} businesses to read · ${_duration(o.hours)}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.faint, fontWeight: FontWeight.w600),
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
