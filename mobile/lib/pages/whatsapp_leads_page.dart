import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';
import 'saved_businesses_page.dart' show StateBadge;

/// Specialized view for leads that have been WhatsApp validated.
class WhatsAppLeadsPage extends StatefulWidget {
  const WhatsAppLeadsPage({super.key});

  @override
  State<WhatsAppLeadsPage> createState() => _WhatsAppLeadsPageState();
}

class _WhatsAppLeadsPageState extends State<WhatsAppLeadsPage> {
  final _repo = LeadRepository();
  String _searchQuery = '';
  final _searchController = TextEditingController();
  late final Stream<List<Lead>> _leadsStream;

  @override
  void initState() {
    super.initState();
    _leadsStream = _repo.getLeadsStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Lead>>(
          stream: _leadsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ScrollableState(
                child: _ErrorState(
                  message: snapshot.error.toString(),
                  onRetry: () async => setState(() {}),
                ),
              );
            }

            final allLeads = snapshot.data ?? const <Lead>[];
            // Filter only WhatsApp validated leads
            final totalWaLeads = allLeads.where((l) => l.hasWhatsApp).toList();
            var waLeads = totalWaLeads;

            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              waLeads = waLeads.where((lead) {
                final name = lead.business.toLowerCase();
                final location = lead.location.toLowerCase();
                final phone = (lead.phone ?? '').toLowerCase();
                return name.contains(query) ||
                    location.contains(query) ||
                    phone.contains(query);
              }).toList();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'WhatsApp Leads',
                  subtitle: totalWaLeads.isEmpty
                      ? 'Validated leads will show up here'
                      : _searchQuery.isEmpty
                          ? '${totalWaLeads.length} total ${totalWaLeads.length == 1 ? 'lead' : 'leads'}'
                          : '${waLeads.length} of ${totalWaLeads.length} leads found',
                  trailing: HeaderBadge(
                    icon: AppIcons.chat,
                    background: t.sageTint,
                    foreground: t.sageDeep,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'Search WhatsApp leads...',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 20, right: 12),
                            child:
                                Icon(AppIcons.search, size: 19, color: t.faint),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(AppIcons.x, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: waLeads.isEmpty
                      ? _ScrollableState(
                          child: _searchQuery.isNotEmpty
                              ? const _NoResultsState()
                              : const _EmptyState(),
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                          itemCount: waLeads.length,
                          itemBuilder: (context, index) {
                            final lead = waLeads[index];
                            return SavedBusinessCard(
                              lead: lead,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BusinessDetailsPage(lead: lead),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateBadge(
          icon: AppIcons.chat,
          background: t.sageTint,
          foreground: t.sageDeep,
        ),
        const SizedBox(height: 20),
        Text(
          'No WhatsApp leads yet',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Validated leads from your searches will appear here automatically.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const StateBadge(icon: AppIcons.searchX),
        const SizedBox(height: 20),
        Text(
          'No matches',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Try a different name, location, or phone number.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StateBadge(
          icon: AppIcons.alert,
          background: t.accentTint,
          foreground: t.accentText,
        ),
        const SizedBox(height: 20),
        Text(
          'Could not load leads',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: t.danger),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(AppIcons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
