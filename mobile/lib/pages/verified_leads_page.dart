import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/paged_query.dart';
import '../services/verified_lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/lead_collection_page.dart';
import '../widgets/verified_lead_card.dart';

/// The WhatsApp-validated 1-star review leads (`whatsappLeads` documents with
/// `sourceType == 'review'`) — the only leads the phone shows.
///
/// Two lists behind a small switch. **New** holds the leads nobody has
/// contacted yet. **Contacted** holds only the leads *this* salesman
/// contacted — a lead another salesman contacted is in neither list. Both are
/// live listeners (see [PagedQueryController]): a lead validated in the web
/// console, or marked contacted by you here or on another of your phones,
/// appears in the right list on its own.
///
/// Opening WhatsApp on a New lead marks it Contacted; "Move to New" puts it
/// back.
class VerifiedLeadsPage extends StatefulWidget {
  const VerifiedLeadsPage({
    super.key,
    this.repository,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  /// For tests; defaults to the Firestore-backed one.
  final VerifiedLeadRepository? repository;

  /// For tests: the query for a collection (default: Firestore's).
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;

  /// For tests: how WhatsApp / Maps are opened.
  final LeadActions actions;

  @override
  State<VerifiedLeadsPage> createState() => _VerifiedLeadsPageState();
}

class _VerifiedLeadsPageState extends State<VerifiedLeadsPage> {
  late final VerifiedLeadRepository _repo = widget.repository ?? VerifiedLeadRepository();

  static const _collection = 'whatsappLeads';
  static const _sourceType = 'review';
  static const _contacted = 'contacted';

  /// Writes the status; the lists follow through their listeners. The
  /// snackbar shows at once — the local write already moved the lead, and a
  /// rejected write moves it back and says why.
  Future<void> _setContacted(VerifiedLead item, {required bool contacted, bool fromUndo = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(_repo.setContacted(_collection, item.lead.id, contacted: contacted).catchError((Object _) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not update the lead. Check your connection.')));
    }));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(contacted ? 'Moved to Contacted' : 'Moved back to New'),
        action: fromUndo
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () => _setContacted(item, contacted: !contacted, fromUndo: true),
              ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return LeadCollectionPage<VerifiedLead>(
      title: 'WhatsApp · 1-star reviews',
      noun: 'business',
      headerIcon: AppIcons.chat,
      searchHint: 'Search WhatsApp leads...',
      emptyIcon: AppIcons.chat,
      emptyTitle: 'No WhatsApp leads here yet',
      emptyBody: 'Leads you validate in the web console appear here, and move to Contacted once you reach out.',
      emptySubtitle: 'Validated leads will land here',
      filters: const [
        (label: 'New', value: null),
        (label: 'Contacted', value: _contacted),
      ],
      controllerFor: (status) {
        final contactedList = status == _contacted;
        Query<Map<String, dynamic>> base(String? category) {
          Query<Map<String, dynamic>> q =
              (widget.collectionQuery ?? FirebaseFirestore.instance.collection)(_collection)
                  .where('sourceType', isEqualTo: _sourceType);
          if (category != null) q = q.where('category', isEqualTo: category);
          return q;
        }

        // Ordering by `contactedAt` also leaves out every lead that has none,
        // so this is exactly the contacted ones — by anyone.
        Query<Map<String, dynamic>> contactedByAnyone(String? category) =>
            base(category).orderBy('contactedAt', descending: true);

        // This salesman's contacted leads only. A lead written while signed
        // out has no `contactedBy`, so the empty fallback matches none.
        final owner = _repo.currentUid ?? '';
        Query<Map<String, dynamic>> myContacted(String? category) =>
            base(category).where('contactedBy', isEqualTo: owner).orderBy('contactedAt', descending: true);

        Future<int> countOf(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;

        return PagedQueryController<VerifiedLead>(
          // The list's true size, so the header says "125 businesses" and not
          // "58+" while only the first pages have loaded. New is everything
          // minus the leads anyone has contacted (`status` can be unset, which
          // Firestore cannot filter for).
          counter: (category) async {
            if (contactedList) return countOf(myContacted(category));
            final all = await countOf(base(category));
            final contacted = await countOf(contactedByAnyone(category));
            return all > contacted ? all - contacted : 0;
          },
          segments: [
            // New: by verified date, with contacted leads dropped.
            (category) => contactedList ? myContacted(category) : base(category).orderBy('updatedAt', descending: true),
          ],
          map: (doc) => VerifiedLead.fromData(Lead.fromDoc(doc), doc.data()),
          include: contactedList ? null : (row) => !row.isContacted,
        );
      },
      // Grouped by the date each list is ordered by.
      dateOf: (row) => row.isContacted ? (row.contactedAt ?? row.shownDate) : row.shownDate,
      searchText: (r) =>
          '${r.lead.business} ${r.lead.location} ${r.lead.phone ?? ''} ${r.lead.category}'.toLowerCase(),
      categoryOf: (r) => r.lead.category,
      itemBuilder: (context, row) => VerifiedLeadCard(
        key: ValueKey(row.lead.id),
        item: row,
        actions: widget.actions,
        onContacted: row.isContacted ? null : () => _setContacted(row, contacted: true),
        onMoveToNew: row.isContacted ? () => _setContacted(row, contacted: false) : null,
      ),
    );
  }
}
