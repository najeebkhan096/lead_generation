import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/saved_business_card.dart';
import 'business_details_page.dart';
import 'saved_businesses_page.dart' show StateBadge;

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _repo = LeadRepository();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Lead>>(
          stream: _repo.getLeadsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allLeads = snapshot.data ?? [];
            final leads = allLeads.where((l) => l.isFavorite).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'My favorites',
                  subtitle: leads.isEmpty
                      ? 'Your shortlist lives here'
                      : '${leads.length} ${leads.length == 1 ? 'business' : 'businesses'} on your shortlist',
                  trailing: HeaderBadge(
                    icon: AppIcons.heart,
                    background: t.accentTint,
                    foreground: t.accentDeep,
                  ),
                ),
                Expanded(
                  child: leads.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                          itemCount: leads.length,
                          itemBuilder: (context, index) {
                            final lead = leads[index];
                            return SavedBusinessCard(
                              lead: lead,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          BusinessDetailsPage(lead: lead)),
                                );
                              },
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

  Widget _buildEmptyState() {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StateBadge(
              icon: AppIcons.heart,
              background: t.accentTint,
              foreground: t.accentDeep,
            ),
            const SizedBox(height: 20),
            Text(
              'No favorites yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the heart on any lead to keep it close.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
