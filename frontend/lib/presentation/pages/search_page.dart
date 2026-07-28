import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import 'results_page.dart';
import 'saved_businesses_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _formKey = GlobalKey<FormState>();

  String _category = 'Dentist';
  String _dateRange = '30';

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
                            'Pick a service — we scan every U.S. state for businesses with recent 1-star reviews. You get phone numbers and Google Maps links. Target: 100 leads.',
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
                          TextFormField(
                            initialValue: _category,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Dentist, Hotel, Restaurant',
                            ),
                            enabled: !loading,
                            onChanged: (v) => _category = v,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Enter a category' : null,
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
                                    '1 star only · phone + Google Maps · up to 100 leads',
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
                            const SizedBox(height: 24),
                            if (state.progress != null) ...[
                              LinearProgressIndicator(
                                value: state.progress!.leadFraction,
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
                                    'Goal: ${state.progress!.targetCount}',
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
