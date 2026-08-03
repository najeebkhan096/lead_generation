import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

class DealsPage extends StatefulWidget {
  const DealsPage({super.key});

  @override
  State<DealsPage> createState() => _DealsPageState();
}

class _DealsPageState extends State<DealsPage> {
  final _repo = LeadRepository();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Active Deals'),
          centerTitle: true,
          bottom: TabBar(
            isScrollable: false,
            indicatorColor: AppTheme.accent,
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.slate.withValues(alpha: 0.5),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'CONTACTED'),
              Tab(text: 'BOOKED'),
              Tab(text: 'DONE'),
            ],
          ),
        ),
        body: SafeArea(
          child: StreamBuilder<List<Lead>>(
            stream: _repo.getLeadsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allLeads = snapshot.data ?? [];
              
              return TabBarView(
                children: [
                  _buildLeadList(allLeads.where((l) => l.status == LeadStatus.contacted).toList(), 'No contacted leads'),
                  _buildLeadList(allLeads.where((l) => l.status == LeadStatus.booked).toList(), 'No booked meetings'),
                  _buildLeadList(allLeads.where((l) => l.status == LeadStatus.dealDone).toList(), 'No completed deals'),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white, size: 10),
          const SizedBox(width: 4),
          Text(
            lead.reputationStatus,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.handshake_outlined, size: 64, color: AppTheme.slate.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'Nothing here',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.slate.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}
