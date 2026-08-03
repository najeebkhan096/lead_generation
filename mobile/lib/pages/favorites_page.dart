import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _repo = LeadRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Favorites'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<List<Lead>>(
          stream: _repo.getLeadsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allLeads = snapshot.data ?? [];
            final leads = allLeads.where((l) => l.isFavorite).toList();

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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => BusinessDetailsPage(lead: lead)),
                    );
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
            Icon(Icons.favorite_border_rounded, size: 64, color: AppTheme.slate.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              'No favorites yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.slate.withOpacity(0.5)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Leads you mark as favorite will appear here for quick access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}
