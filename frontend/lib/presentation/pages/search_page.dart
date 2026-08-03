import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/business_categories.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import 'active_search_page.dart';
import 'results_page.dart';
import 'saved_businesses_page.dart';
import 'whatsapp_checker_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final List<String> _targetServices = [];

  String _dateRange = '30';
  bool _autoSave = true;
  bool _analyze = false;

  static const _dateRanges = <String, String>{
    '7': 'Last 7 days',
    '30': 'Last 30 days',
    '90': 'Last 90 days',
    '365': 'Last 365 days',
  };

  @override
  void initState() {
    super.initState();
    // Search progress lives only in the backend's in-memory store, so on a
    // fresh page load, check whether a search is already running or just
    // finished server-side instead of silently showing a blank form.
    context.read<SearchBloc>().add(const SearchResumeChecked());
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
    setState(() {
      _targetServices.remove(service);
    });
  }

  void _submit() {
    if (_targetServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one service to start searching')),
      );
      return;
    }
    context.read<SearchBloc>().add(
          SearchSubmitted(
            categories: List.from(_targetServices),
            dateRange: _dateRange,
            nationwide: true,
            autoSave: _autoSave,
            analyze: _analyze,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchBloc, SearchState>(
      listenWhen: (prev, next) => prev.status != next.status,
      listener: (context, state) {
        if (state.status == SearchStatus.loading) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ActiveSearchPage()),
          );
        }
      },
      builder: (context, state) {
        final loading = state.status == SearchStatus.loading;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF0F4F8),
                  Color(0xFFE8F5F3),
                  Color(0xFFF7F3EB),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  'LeadFinder',
                                  style: Theme.of(context).textTheme.displaySmall,
                                ),
                              ),
                              _ActionButton(
                                icon: Icons.chat_outlined,
                                label: 'WhatsApp',
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppCheckerPage())),
                              ),
                              const SizedBox(width: 12),
                              _ActionButton(
                                icon: Icons.history_rounded,
                                label: 'History',
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedBusinessesPage())),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Select multiple services to scan across the entire USA. The search will process each service sequentially and auto-save results to Firebase.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 36),
                          Text(
                            'Coverage',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF6EE7B7)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.public, color: AppTheme.accent, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'All 50 U.S. states + D.C. (automatic)',
                                    style: TextStyle(
                                      color: AppTheme.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Business Categories',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
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
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      decoration: const InputDecoration(
                                        hintText: 'Select or type a category...',
                                        isDense: true,
                                      ),
                                      enabled: !loading,
                                      onFieldSubmitted: (v) {
                                        _addService(v);
                                        controller.clear();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filled(
                                    onPressed: loading ? null : () {
                                      _addService(controller.text);
                                      controller.clear();
                                    },
                                    icon: const Icon(Icons.add),
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 512,
                                    constraints: const BoxConstraints(maxHeight: 250),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (BuildContext context, int index) {
                                        final String option = options.elementAt(index);
                                        return InkWell(
                                          onTap: () => onSelected(option),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
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
                              'Target Services:',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.slate,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _targetServices.map((service) => Chip(
                                label: Text(service),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: loading ? null : () => _removeService(service),
                                backgroundColor: Colors.white,
                                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: const BorderSide(color: AppTheme.line),
                                ),
                              )).toList(),
                            ),
                            const SizedBox(height: 16),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'Review Filter',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.warnSoft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFCD34D)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.star, color: AppTheme.warn, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '1 star only · phone + Google Maps · exhaustive scan',
                                    style: TextStyle(
                                      color: Color(0xFFB45309),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Date Range',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _dateRange,
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
                          Text(
                            'Search Options',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  title: const Text('Auto-save to Firebase', style: TextStyle(fontSize: 14)),
                                  subtitle: const Text('Saves each niche immediately', style: TextStyle(fontSize: 11)),
                                  value: _autoSave,
                                  onChanged: loading ? null : (v) => setState(() => _autoSave = v ?? true),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  dense: true,
                                ),
                              ),
                              Expanded(
                                child: CheckboxListTile(
                                  title: const Text('Analyze Reviews', style: TextStyle(fontSize: 14)),
                                  subtitle: const Text('Categorize complaints', style: TextStyle(fontSize: 11)),
                                  value: _analyze,
                                  onChanged: loading ? null : (v) => setState(() => _analyze = v ?? false),
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: loading ? null : _submit,
                            child: const Text('Start Sequential Search'),
                          ),
                          if (state.status == SearchStatus.failure && state.error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              state.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFB91C1C)),
                            ),
                          ],
                        ],
                      ),
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accent)),
          ],
        ),
      ),
    );
  }
}
