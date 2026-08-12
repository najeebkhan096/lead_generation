import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/business_categories.dart';
import '../../core/constants/search_countries.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/repositories/lead_repository.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import 'multi_scan_page.dart';

/// Configures and kicks off a new nationwide scan. Reachable from the
/// Dashboard's "New Search" action.
///
/// A single category still runs through the classic [SearchBloc] flow —
/// the shell above this page owns navigating to `ActiveSearchPage` the
/// moment that search starts. Two or more categories run through the
/// concurrent worker-pool endpoint instead (each category scans
/// independently, picking up the next queued one as soon as it finishes,
/// rather than one at a time), landing on [MultiScanPage] for live
/// per-category progress.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final List<String> _targetServices = [];

  String _dateRange = '365';
  String _country = 'US';
  bool _allCountries = false;
  bool _autoSave = true;
  bool _analyze = false;
  int _concurrency = 4;
  bool _startingMultiSearch = false;

  static const _dateRanges = <String, String>{
    '7': 'Last 7 days',
    '30': 'Last 30 days',
    '90': 'Last 90 days',
    '365': 'Last 365 days',
  };

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
    setState(() {
      _targetServices.remove(service);
    });
  }

  Future<void> _submit() async {
    if (_targetServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one service to start searching')),
      );
      return;
    }

    // A single category normally runs through the classic sequential flow —
    // but "all countries" needs true concurrency (one worker per country),
    // which only the worker-pool endpoint provides, so it always routes
    // there even for just one category.
    if (_targetServices.length == 1 && !_allCountries) {
      context.read<SearchBloc>().add(
            SearchSubmitted(
              categories: List.from(_targetServices),
              dateRange: _dateRange,
              nationwide: true,
              autoSave: _autoSave,
              analyze: _analyze,
              country: _country,
            ),
          );
      return;
    }

    setState(() => _startingMultiSearch = true);
    try {
      await context.read<LeadRepository>().startMultiSearch(
            categories: List.from(_targetServices),
            countries: _allCountries ? SearchCountries.list.map((c) => c.code).toList() : null,
            concurrency: _concurrency,
            dateRange: _dateRange,
            analyze: _analyze,
            country: _country,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MultiScanPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _startingMultiSearch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        final isMulti = _targetServices.length > 1;
        final usesWorkerPool = isMulti || _allCountries;
        final loading = usesWorkerPool ? _startingMultiSearch : state.status == SearchStatus.loading;

        return Scaffold(
          appBar: AppBar(title: const Text('New Search')),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Select multiple services to scan across the entire country. The search runs each service in sequence and auto-saves results to Firebase.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 28),
                        _SectionLabel('Country'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _country,
                          icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                          items: SearchCountries.list
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.code,
                                  child: Text(c.name),
                                ),
                              )
                              .toList(),
                          onChanged: (loading || _allCountries)
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _country = v);
                                },
                        ),
                        const SizedBox(height: 10),
                        _OptionToggle(
                          title: 'Search in all countries',
                          subtitle:
                              'Runs every category against all ${SearchCountries.list.length} countries at once, in parallel',
                          value: _allCountries,
                          onChanged: loading ? null : (v) => setState(() => _allCountries = v),
                        ),
                        const SizedBox(height: 12),
                        _SectionLabel('Coverage'),
                        const SizedBox(height: 8),
                        _InfoBanner(
                          icon: AppIcons.globe,
                          color: AppTheme.sage700,
                          background: AppTheme.sage100,
                          text: _allCountries
                              ? 'All ${SearchCountries.list.length} countries at once — ${SearchCountries.list.map((c) => c.shortName).join(', ')} (parallel)'
                              : SearchCountries.byCode(_country).coverageLabel,
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel('Business categories'),
                        const SizedBox(height: 8),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<String>.empty();
                            }
                            return BusinessCategories.top100.where((String option) {
                              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                            });
                          },
                          onSelected: (String selection) {
                            _addService(selection);
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
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
                                    enabled: !loading,
                                    onFieldSubmitted: (v) {
                                      _addService(v);
                                      controller.clear();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filled(
                                  onPressed: loading
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
                                    itemBuilder: (BuildContext context, int index) {
                                      final String option = options.elementAt(index);
                                      return InkWell(
                                        onTap: () => onSelected(option),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 18, vertical: 13),
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
                          Text(
                            'Target services',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.subtle,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _targetServices
                                .map((service) => Chip(
                                      label: Text(service),
                                      deleteIcon: const Icon(AppIcons.close, size: 14),
                                      onDeleted: loading ? null : () => _removeService(service),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 8),
                        _SectionLabel('Review filter'),
                        const SizedBox(height: 8),
                        _InfoBanner(
                          icon: AppIcons.star,
                          color: AppTheme.accent700,
                          background: AppTheme.accent100,
                          text: '1 star only · phone + Google Maps · exhaustive scan',
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel('Date range'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _dateRange,
                          icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                          items: _dateRanges.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: loading
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _dateRange = v);
                                },
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel('Search options'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _OptionToggle(
                                title: 'Auto-save to Firebase',
                                subtitle: 'Saves each niche immediately',
                                value: _autoSave,
                                onChanged: loading ? null : (v) => setState(() => _autoSave = v),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _OptionToggle(
                                title: 'Analyze reviews',
                                subtitle: 'Categorize complaints',
                                value: _analyze,
                                onChanged: loading ? null : (v) => setState(() => _analyze = v),
                              ),
                            ),
                          ],
                        ),
                        if (usesWorkerPool) ...[
                          const SizedBox(height: 20),
                          _SectionLabel('Parallel workers'),
                          const SizedBox(height: 8),
                          _InfoBanner(
                            icon: AppIcons.zap,
                            color: AppTheme.sage700,
                            background: AppTheme.sage100,
                            text: _allCountries
                                ? '${_targetServices.length} categor${_targetServices.length == 1 ? 'y' : 'ies'} × ${SearchCountries.list.length} countries = ${_targetServices.length * SearchCountries.list.length} scans will run concurrently — each worker picks up the next one as soon as it finishes.'
                                : '${_targetServices.length} categories will scan concurrently instead of one at a time — each worker picks up the next category as soon as it finishes.',
                          ),
                          const SizedBox(height: 10),
                          _ConcurrencySlider(
                            value: _concurrency,
                            onChanged: loading ? null : (v) => setState(() => _concurrency = v),
                          ),
                        ],
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed: loading ? null : _submit,
                          child: loading && usesWorkerPool
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.surface),
                                )
                              : Text(usesWorkerPool ? 'Start $_concurrency-worker scan' : 'Start search'),
                        ),
                        if (state.status == SearchStatus.failure && state.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            state.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.danger),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConcurrencySlider extends StatelessWidget {
  const _ConcurrencySlider({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Row(
        children: [
          const Icon(AppIcons.users, size: 18, color: AppTheme.accent700),
          const SizedBox(width: 10),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: 2,
              max: 8,
              divisions: 6,
              activeColor: AppTheme.accent500,
              label: '$value workers',
              onChanged: onChanged == null ? null : (v) => onChanged!(v.round()),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$value workers',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? AppTheme.accent100 : AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                value ? AppIcons.checkCircle : Icons.circle_outlined,
                size: 20,
                color: value ? AppTheme.accent700 : AppTheme.neutral400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: value ? AppTheme.accent800 : AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: AppTheme.faint),
                    ),
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
