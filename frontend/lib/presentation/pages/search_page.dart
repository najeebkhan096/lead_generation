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
  final _locationController = TextEditingController(text: 'New York');
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

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<SearchBloc>().add(
          SearchSubmitted(
            location: _locationController.text.trim(),
            category: _category,
            dateRange: _dateRange,
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
                            'Find USA businesses with recent 1-star Google reviews — free, no paid APIs, no database.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 36),
                          Text(
                            'Location',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _locationController,
                            enabled: !loading,
                            decoration: const InputDecoration(
                              hintText: 'New York, California, Texas…',
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Enter a location' : null,
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
                                Text(
                                  '1 star only',
                                  style: TextStyle(
                                    color: AppTheme.warn,
                                    fontWeight: FontWeight.w700,
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
                                : const Text('Find Leads'),
                          ),
                          if (loading) ...[
                            const SizedBox(height: 16),
                            Text(
                              state.progressMessage ??
                                  'Scraping public maps pages… this can take several minutes.',
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
