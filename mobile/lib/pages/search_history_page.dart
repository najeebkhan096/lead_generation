import 'package:flutter/material.dart';

import '../models/search_batch.dart';
import '../services/lead_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'saved_businesses_page.dart' show StateBadge;

/// Every past search run, live from Firestore's `searches` collection.
class SearchHistoryPage extends StatelessWidget {
  SearchHistoryPage({super.key});

  final _repo = LeadRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search history')),
      body: SafeArea(
        child: StreamBuilder<List<SavedSearch>>(
          stream: _repo.getSearchesStream(),
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

            final searches = snapshot.data ?? const <SavedSearch>[];
            if (searches.isEmpty) {
              return const _CenteredMessage(
                icon: AppIcons.history,
                title: 'No searches yet',
                message:
                    'Searches you run in LeadFinder web will show up here.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              itemCount: searches.length,
              itemBuilder: (context, index) =>
                  _SearchCard(search: searches[index]),
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
