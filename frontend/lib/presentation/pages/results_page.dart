import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../bloc/search/search_bloc.dart';
import '../bloc/search/search_event.dart';
import '../bloc/search/search_state.dart';
import '../utils/web_download.dart';
import '../widgets/lead_card.dart';

class ResultsPage extends StatelessWidget {
  const ResultsPage({super.key});

  void _handleExport(BuildContext context, SearchBloc bloc, {required bool csv}) {
    if (csv) {
      bloc.add(const ExportCsvRequested());
    } else {
      bloc.add(const ExportJsonRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchBloc, SearchState>(
      listenWhen: (p, n) => p.exportMessage != n.exportMessage && n.exportMessage != null,
      listener: (context, state) {
        final bloc = context.read<SearchBloc>();
        if (bloc.lastExportContent != null && bloc.lastExportFilename != null) {
          final isCsv = bloc.lastExportFilename!.endsWith('.csv');
          downloadTextFile(
            bloc.lastExportFilename!,
            bloc.lastExportContent!,
            isCsv ? 'text/csv' : 'application/json',
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.exportMessage!)),
        );
      },
      builder: (context, state) {
        final bloc = context.read<SearchBloc>();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Results'),
            actions: [
              if (state.leads.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () => _handleExport(context, bloc, csv: true),
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('CSV'),
                ),
                TextButton.icon(
                  onPressed: () => _handleExport(context, bloc, csv: false),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('JSON'),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF0F4F8), Color(0xFFE8F5F3)],
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: state.leads.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'No leads with WhatsApp-available numbers',
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Try a different city or category. Google Maps markup can also block review extraction occasionally — re-run the search.',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('New Search'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          Text(
                            '${state.leads.length} leads · ${state.category} in ${state.location}',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.ink,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '1-star + WhatsApp · last ${state.dateRange} days · in-memory only',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 18),
                          ...state.leads.map((lead) => LeadCard(lead: lead)),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
