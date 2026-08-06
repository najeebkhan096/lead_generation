import 'package:firebase_auth/firebase_auth.dart';
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

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Lead>>(
          stream: _leadsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allLeads = snapshot.data ?? [];
            var leads = allLeads
                .where((l) => l.isFavorite && l.assignedTo == user?.uid)
                .toList();

            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              leads = leads.where((lead) {
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
                  title: 'My favorites',
                  subtitle: leads.isEmpty && _searchQuery.isEmpty
                      ? 'Your shortlist lives here'
                      : '${leads.length} ${leads.length == 1 ? 'business' : 'businesses'} on your shortlist',
                  trailing: HeaderBadge(
                    icon: AppIcons.heart,
                    background: t.accentTint,
                    foreground: t.accentDeep,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search favorites...',
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
                const SizedBox(height: 12),
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
              icon: _searchQuery.isNotEmpty ? AppIcons.searchX : AppIcons.heart,
              background: t.accentTint,
              foreground: t.accentDeep,
            ),
            const SizedBox(height: 20),
            Text(
              _searchQuery.isNotEmpty ? 'No matches' : 'No favorites yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different name, location, or phone number.'
                  : 'Tap the heart on any lead to keep it close.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
