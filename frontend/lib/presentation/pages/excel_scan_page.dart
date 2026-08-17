import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/business_categories.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/repositories/lead_repository.dart';

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
  int _concurrency = 4;
  bool _starting = false;

  static const _dateRanges = <String, String>{
    '7': 'Last 7 days',
    '28': 'Last 28 days',
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
      await context.read<LeadRepository>().startStateScan(
            categories: List.from(_targetServices),
            concurrency: _concurrency,
            dateRange: _dateRange,
          );
      if (!mounted) return;
      context.pushReplacement('/scan-progress');
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
                    'Scans every US state one at a time — within the active state, cities '
                    'are scraped in parallel across your worker pool. Nothing is saved to '
                    'your Leads list; each category becomes one Excel workbook (one sheet '
                    'per state), auto-saved to Firebase the instant each state finishes so '
                    'nothing scanned is ever lost, even if a scan is interrupted.',
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

