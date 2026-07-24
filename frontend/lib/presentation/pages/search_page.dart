import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import 'results_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _formKey = GlobalKey<FormState>();

  String _category = 'Dentist';
  String _dateRange = '30';

  static const _categories = [
    'Restaurant',
    'Dentist',
    'Salon',
    'Hotel',
    'Car Dealer',
    'Contractor',
    'Lawyer',
  ];

  static const _dateRanges = <String, String>{
    '7': 'Last 7 days',
    '30': 'Last 30 days',
    '90': 'Last 90 days',
    '365': 'Last 365 days',
  };

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SearchBloc>().add(
          SearchSubmitted(
            category: _category,
            dateRange: _dateRange,
            nationwide: true,
            targetLeadCount: 100,
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
                          Text(
                            'LeadFinder',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Pick a service — we scan every U.S. state for businesses with recent 1-star reviews and a WhatsApp number. Target: 100 leads.',
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
                            'Business Category',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _category,
                            items: _categories
                                .map(
                                  (c) => DropdownMenuItem(value: c, child: Text(c)),
                                )
                                .toList(),
                            onChanged: loading
                                ? null
                                : (v) {
                                    if (v != null) setState(() => _category = v);
                                  },
                          ),
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
                                    '1 star only · WhatsApp number required · up to 100 leads',
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
                                : const Text('Find 100 Leads Nationwide'),
                          ),
                          if (loading) ...[
                            const SizedBox(height: 16),
                            Text(
                              state.progressMessage ??
                                  'Scanning U.S. states… this can take a long time (hours for 100 leads). Keep this tab open.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
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
