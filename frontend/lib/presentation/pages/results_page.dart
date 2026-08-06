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
      listenWhen: (p, n) =>
          (p.exportMessage != n.exportMessage && n.exportMessage != null) ||
          (p.saveMessage != n.saveMessage && n.saveMessage != null),
      listener: (context, state) {
        final bloc = context.read<SearchBloc>();
        if (bloc.lastExportContent != null &&
            bloc.lastExportFilename != null &&
            state.exportMessage != null &&
            state.exportMessage!.contains('ready')) {
          final isCsv = bloc.lastExportFilename!.endsWith('.csv');
          downloadTextFile(
            bloc.lastExportFilename!,
            bloc.lastExportContent!,
            isCsv ? 'text/csv' : 'application/json',
          );
        }
        final message = state.saveMessage ?? state.exportMessage;
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
      builder: (context, state) {
        final bloc = context.read<SearchBloc>();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Results'),
            actions: [
              if (state.leads.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: state.savingToDb
                      ? null
                      : () => bloc.add(const SaveToDatabaseRequested()),
                  icon: state.savingToDb
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.cloudUpload, size: 18),
                  label: Text(state.savingToDb ? 'Saving…' : 'Firebase'),
                ),
                TextButton.icon(
                  onPressed: () => _handleExport(context, bloc, csv: true),
                  icon: const Icon(AppIcons.download, size: 18),
                  label: const Text('CSV'),
                ),
                TextButton.icon(
                  onPressed: () => _handleExport(context, bloc, csv: false),
                  icon: const Icon(AppIcons.download, size: 18),
                  label: const Text('JSON'),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: state.leads.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: const BoxDecoration(
                                  color: AppTheme.accent100, shape: BoxShape.circle),
                              child: const Icon(AppIcons.searchX,
                                  size: 36, color: AppTheme.accent700),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No businesses found',
                              style: Theme.of(context).textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Try a different category or date range, then run the search again.',
                              style: Theme.of(context).textTheme.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Back to dashboard'),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        children: [
                          Text(
                            '${state.leads.length} leads · ${state.category} in ${state.location}',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.ink,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '1-star reviews · last ${state.dateRange} days · phone + Maps · tap Save to Firebase for the mobile app',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: state.savingToDb
                                  ? null
                                  : () => bloc.add(const SaveToDatabaseRequested()),
                              icon: state.savingToDb
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.surface,
                                      ),
                                    )
                                  : const Icon(AppIcons.cloudUpload, size: 19),
                              label: Text(
                                state.savingToDb
                                    ? 'Saving to Firebase…'
                                    : 'Save to Firebase',
                              ),
                            ),
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
