import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/business_categories.dart';
import '../../core/constants/search_countries.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/repositories/lead_repository.dart';
import 'multi_scan_page.dart';

/// Configures and starts an "Excel scan" — runs the exact same concurrent
/// multi-category scraping engine as the normal Multi-Category Scan, but
/// skips writing individual businesses to Firestore entirely. Once every
/// category finishes, the results are packaged into one .xlsx workbook
/// (one sheet per category) and uploaded straight to Firebase Storage —
/// see [MultiScanPage] for the live-progress/archive-ready view, and the
/// Excel Archive page for browsing everything saved this way.
class ExcelScanPage extends StatefulWidget {
  const ExcelScanPage({super.key});

  @override
  State<ExcelScanPage> createState() => _ExcelScanPageState();
}

class _ExcelScanPageState extends State<ExcelScanPage> {
  final _categoryController = TextEditingController();
  final List<String> _targetServices = [];

  String _dateRange = '365';
  String _country = 'US';
  bool _allCountries = false;
  int _concurrency = 4;
  bool _starting = false;

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
    setState(() => _targetServices.remove(service));
  }

  Future<void> _submit() async {
    if (_targetServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one service to start scanning')),
      );
      return;
    }

    setState(() => _starting = true);
    try {
      await context.read<LeadRepository>().startMultiSearch(
            categories: List.from(_targetServices),
            countries: _allCountries ? SearchCountries.list.map((c) => c.code).toList() : null,
            concurrency: _concurrency,
            dateRange: _dateRange,
            exportOnly: true,
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
                    'Runs the same nationwide scan as a normal search, but nothing '
                    'is saved to your Leads list — the results are packaged into one '
                    'Excel workbook (one sheet per category) and uploaded to Firebase '
                    'automatically once the scan finishes.',
                    style: Theme.of(context).textTheme.bodyLarge,
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
                  const SizedBox(height: 24),
                  Text('Country', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _country,
                    icon: const Icon(AppIcons.chevronDown, size: 18, color: AppTheme.accent),
                    items: SearchCountries.list
                        .map((c) => DropdownMenuItem(value: c.code, child: Text(c.name)))
                        .toList(),
                    onChanged: (_starting || _allCountries)
                        ? null
                        : (v) {
                            if (v != null) setState(() => _country = v);
                          },
                  ),
                  const SizedBox(height: 10),
                  _ExcelOptionToggle(
                    title: 'Search in all countries',
                    subtitle: 'Runs every category against all ${SearchCountries.list.length} countries at once',
                    value: _allCountries,
                    onChanged: _starting ? null : (v) => setState(() => _allCountries = v),
                  ),
                  const SizedBox(height: 20),
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
                            min: 2,
                            max: 8,
                            divisions: 6,
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
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _starting ? null : _submit,
                    child: _starting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppTheme.surface),
                          )
                        : const Text('Start Excel scan'),
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

class _ExcelOptionToggle extends StatelessWidget {
  const _ExcelOptionToggle({
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
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.faint)),
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
