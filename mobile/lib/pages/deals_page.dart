import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';
import 'saved_businesses_page.dart' show StateBadge;

class DealsPage extends StatefulWidget {
  const DealsPage({super.key});

  @override
  State<DealsPage> createState() => _DealsPageState();
}

class _DealsPageState extends State<DealsPage> {
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
    final user = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: StreamBuilder<List<Lead>>(
            stream: _leadsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allLeads = snapshot.data ?? [];
              final myLeads = allLeads.where((l) => l.assignedTo == user?.uid).toList();

              var contacted =
                  myLeads.where((l) => l.status == LeadStatus.contacted).toList();
              var booked =
                  myLeads.where((l) => l.status == LeadStatus.booked).toList();
              var done =
                  myLeads.where((l) => l.status == LeadStatus.dealDone).toList();

              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                contacted = contacted
                    .where((l) => l.business.toLowerCase().contains(query))
                    .toList();
                booked = booked
                    .where((l) => l.business.toLowerCase().contains(query))
                    .toList();
                done = done
                    .where((l) => l.business.toLowerCase().contains(query))
                    .toList();
              }

              final totalFiltered = contacted.length + booked.length + done.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Active deals',
                    subtitle: totalFiltered == 0
                        ? 'Your pipeline at a glance'
                        : '$totalFiltered ${totalFiltered == 1 ? 'deal' : 'deals'} in your pipeline',
                    trailing: HeaderBadge(
                      icon: AppIcons.handshake,
                      background: t.sageTint,
                      foreground: t.sageDeep,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search deals...',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 20, right: 12),
                          child: Icon(AppIcons.search, size: 19, color: t.faint),
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
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Row(
                      children: [
                        _StatTile(
                          label: 'Contacted',
                          count: contacted.length,
                          icon: AppIcons.send,
                          background: t.accentTint,
                          foreground: t.accentTextStrong,
                        ),
                        const SizedBox(width: 10),
                        _StatTile(
                          label: 'Orders',
                          count: booked.length,
                          icon: AppIcons.packageCheck,
                          background: t.sageTint,
                          foreground: t.sageTextStrong,
                        ),
                        const SizedBox(width: 10),
                        _StatTile(
                          label: 'Won',
                          count: done.length,
                          icon: AppIcons.circleCheck,
                          background: t.sage,
                          foreground: t.onFill,
                        ),
                      ],
                    ),
                  ),
                  const _SegmentedTabs(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLeadList(contacted, 'No contacted leads'),
                        _buildLeadList(booked, 'No orders placed yet'),
                        _buildLeadList(done, 'No completed deals'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLeadList(List<Lead> leads, String emptyMessage) {
    if (leads.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: leads.length,
      itemBuilder: (context, index) {
        final lead = leads[index];
        return Stack(
          children: [
            SavedBusinessCard(
              lead: lead,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BusinessDetailsPage(lead: lead)),
                );
              },
            ),
            Positioned(
              top: 12,
              right: 45,
              child: _buildReputationIndicator(lead),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReputationIndicator(Lead lead) {
    if (lead.reputationStatus.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.sparkles, color: t.onFill, size: 11),
          const SizedBox(width: 4),
          Text(
            lead.reputationStatus,
            style: TextStyle(
              color: t.onFill,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StateBadge(
              icon: AppIcons.handshake,
              background: t.sageTint,
              foreground: t.sageDeep,
            ),
            const SizedBox(height: 20),
            Text(
              'Nothing here',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pipeline tabs styled as a rounded segmented control.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: t.accent,
          borderRadius:
              const BorderRadius.all(Radius.circular(AppTheme.radiusPill)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: t.onFill,
        unselectedLabelColor: t.subtle,
        splashBorderRadius: BorderRadius.circular(AppTheme.radiusPill),
        tabs: const [
          Tab(height: 40, text: 'Contacted'),
          Tab(height: 40, text: 'Orders'),
          Tab(height: 40, text: 'Done'),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
