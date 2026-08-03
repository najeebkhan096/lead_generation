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
  late Future<List<Lead>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Lead>> _load() async {
    final leads = await _repo.fetchAllLeads();
    return leads.where((l) => l.status != LeadStatus.lead).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Deals'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Lead>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final leads = snapshot.data ?? [];

            if (leads.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              itemCount: leads.length,
              itemBuilder: (context, index) {
                final lead = leads[index];
                return SavedBusinessCard(
                  lead: lead,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => BusinessDetailsPage(lead: lead)),
                    );
                    _refresh();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.handshake_outlined, size: 64, color: AppTheme.slate.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              'No active deals',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.slate.withOpacity(0.5)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Move leads to "Contacted" or "Booked" to track your business progress here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}
