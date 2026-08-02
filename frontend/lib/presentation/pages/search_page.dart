import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/business_categories.dart';
import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
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
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchBloc, SearchState>(
      listenWhen: (prev, next) =>
          prev.status != next.status && next.status == SearchStatus.success,
      listener: (context, state) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResultsPage()),
        );
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'LeadFinder',
                                  style: Theme.of(context).textTheme.displaySmall,
                                ),
                              ),
                              IconButton(
                                tooltip: 'WhatsApp Checker',
                                icon: const Icon(Icons.chat_outlined, color: AppTheme.accent),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const WhatsAppCheckerPage()),
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Saved Businesses',
                                icon: const Icon(Icons.manage_search_rounded, color: AppTheme.accent),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SavedBusinessesPage()),
                                  );
                                },
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
                                  borderSide: const BorderSide(color: AppTheme.line),
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
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: loading ? null : _submit,
                            child: loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Start Sequential Search'),
                          ),
                          if (loading) ...[
                            const SizedBox(height: 24),
                            if (state.progress != null) ...[
                              LinearProgressIndicator(
                                value: state.progress!.statesFraction ?? state.progress!.leadFraction,
                                backgroundColor: Colors.black.withOpacity(0.06),
                                color: AppTheme.accent,
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${state.leads.length} leads found',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Full USA Scan',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        _ProgressStat(
                                          label: 'STATES',
                                          value: '${state.progress!.statesDone}/${state.progress!.statesTotal > 0 ? state.progress!.statesTotal : 51}',
                                          icon: Icons.map_outlined,
                                        ),
                                        Container(width: 1, height: 30, color: Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 16)),
                                        _ProgressStat(
                                          label: 'SCANNED',
                                          value: '${state.progress!.businessesScraped}',
                                          icon: Icons.search_rounded,
                                        ),
                                        Container(width: 1, height: 30, color: Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 16)),
                                        _ProgressStat(
                                          label: 'YIELD',
                                          value: '${state.leads.isEmpty || state.progress!.businessesScraped == 0 ? 0 : (state.leads.length / state.progress!.businessesScraped * 100).toStringAsFixed(1)}%',
                                          icon: Icons.analytics_outlined,
                                        ),
                                      ],
                                    ),
                                    if (state.progress!.statesTotal > 0) ...[
                                      const SizedBox(height: 16),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: state.progress!.statesFraction,
                                          backgroundColor: Colors.black.withOpacity(0.03),
                                          color: AppTheme.slate.withOpacity(0.4),
                                          minHeight: 3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                            Text(
                              state.progress?.message ??
                                  'Scanning U.S. states… much faster now. Keep this tab open.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: AppTheme.slate.withOpacity(0.8),
                              ),
                            ),
                            if (state.leads.isNotEmpty) ...[
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  const Icon(Icons.bolt, color: AppTheme.accent, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'LIVE FEED',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.accent,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...state.leads.reversed.take(5).map((lead) => InkWell(
                                    onTap: () {
                                      if (lead.mapsUrl != null) {
                                        launchUrl(Uri.parse(lead.mapsUrl!));
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.black.withOpacity(0.1)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle,
                                              color: Colors.green, size: 16),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  lead.business,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 14),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  lead.location,
                                                  style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (lead.rating != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber[100],
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '★ ${lead.rating}',
                                                style: TextStyle(
                                                  color: Colors.amber[900],
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 8),
                                          Icon(Icons.open_in_new, size: 14, color: Colors.grey[400]),
                                        ],
                                      ),
                                    ),
                                  )),
                              if (state.leads.length > 5)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '+ ${state.leads.length - 5} more leads hidden',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                            ],
                          ],
                          if (state.status == SearchStatus.failure && state.error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              state.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFB91C1C)),
                            ),
                          ],
                          if (state.leads.isNotEmpty && state.status == SearchStatus.success) ...[
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ResultsPage()),
                                );
                              },
                              child: Text('View ${state.leads.length} results'),
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

class _ProgressStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ProgressStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppTheme.slate.withOpacity(0.6)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.ink,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
