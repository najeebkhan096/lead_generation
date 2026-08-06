import 'package:flutter/material.dart';

import '../models/search_batch.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/page_header.dart';
import 'saved_businesses_page.dart' show StateBadge;

/// Every past search run, live from Firestore's `searches` collection.
class SearchHistoryPage extends StatefulWidget {
  const SearchHistoryPage({super.key});

  @override
  State<SearchHistoryPage> createState() => _SearchHistoryPageState();
}

class _SearchHistoryPageState extends State<SearchHistoryPage> {
  final _repo = LeadRepository();
  String _searchQuery = '';
  final _searchController = TextEditingController();
  late final Stream<List<SavedSearch>> _searchesStream;

  @override
  void initState() {
    super.initState();
    _searchesStream = _repo.getSearchesStream();
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
        child: StreamBuilder<List<SavedSearch>>(
          stream: _searchesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _CenteredMessage(
                icon: AppIcons.alert,
                title: 'Could not load searches',
                message: snapshot.error.toString(),
                danger: true,
              );
            }

            final allSearches = snapshot.data ?? const <SavedSearch>[];
            var searches = allSearches;

            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              searches = searches.where((s) {
                return s.category.toLowerCase().contains(query) ||
                    s.location.toLowerCase().contains(query);
              }).toList();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Search history',
                  subtitle: searches.isEmpty && _searchQuery.isEmpty
                      ? 'Past searches live here'
                      : '${searches.length} ${searches.length == 1 ? 'search' : 'searches'} performed',
                  trailing: HeaderBadge(
                    icon: AppIcons.history,
                    background: t.neutralTint,
                    foreground: t.subtle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText: 'Search history...',
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
                  child: searches.isEmpty
                      ? _CenteredMessage(
                          icon: _searchQuery.isNotEmpty
                              ? AppIcons.searchX
                              : AppIcons.history,
                          title: _searchQuery.isNotEmpty
                              ? 'No matches'
                              : 'No searches yet',
                          message: _searchQuery.isNotEmpty
                              ? 'Try a different category or location.'
                              : 'Searches you run in LeadFinder web will show up here.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          itemCount: searches.length,
                          itemBuilder: (context, index) =>
                              _SearchCard(search: searches[index]),
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

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.search});

  final SavedSearch search;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final date = formatDate(search.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.neutralTint,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.search, size: 19, color: t.subtle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  search.category,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (search.location.isNotEmpty) ...[
                      Icon(AppIcons.mapPin, size: 13, color: t.faint),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          search.location,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (date != null) ...[
                      if (search.location.isNotEmpty)
                        Text('  ·  ',
                            style: Theme.of(context).textTheme.bodySmall),
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (search.leadCount != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: t.sageTint,
                borderRadius: const BorderRadius.all(
                    Radius.circular(AppTheme.radiusPill)),
              ),
              child: Text(
                '${search.leadCount} found',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.sageTextStrong,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StateBadge(
              icon: icon,
              background: danger ? t.accentTint : null,
              foreground: danger ? t.accentText : null,
            ),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
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
