import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/paged_query.dart';
import '../services/verified_lead_repository.dart';
import '../theme/app_theme.dart';
import '../utils/outreach_email.dart';
import '../widgets/lead_collection_page.dart';
import '../widgets/verified_lead_card.dart';

/// Which validation a verified-leads list is the output of.
enum VerifiedKind {
  whatsapp(collection: 'whatsappLeads', title: 'WhatsApp'),
  email(collection: 'emailLeads', title: 'Email');

  const VerifiedKind({required this.collection, required this.title});

  /// Firestore collection the web console's validators write to.
  final String collection;
  final String title;
}

/// How a signal is stored on the verified documents (`sourceType`) and named
/// on screen.
extension LeadSignalLabels on LeadSignal {
  String get sourceType => this == LeadSignal.review ? 'review' : 'website';

  String get title => this == LeadSignal.review ? '1-star reviews' : 'No website';
}

/// The verified leads of one channel (WhatsApp or Email) for one signal
/// (1-star review or no website) — e.g. "WhatsApp · 1-star reviews".
///
/// Two lists behind a small switch, **New** (not yet contacted) and
/// **Contacted**. Both are live listeners (see [PagedQueryController]): a lead
/// validated in the web console, or marked contacted here or on another
/// phone, appears in the right list on its own.
///
/// Contacting a New lead (WhatsApp / Email / Call) marks it Contacted;
/// "Move to New" puts it back.
class VerifiedLeadsPage extends StatefulWidget {
  const VerifiedLeadsPage({
    super.key,
    required this.kind,
    required this.signal,
    this.repository,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  final VerifiedKind kind;
  final LeadSignal signal;

  /// For tests; defaults to the Firestore-backed one.
  final VerifiedLeadRepository? repository;

  /// For tests: the query for a collection (default: Firestore's).
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;

  /// For tests: how WhatsApp / email / dialer are opened.
  final LeadActions actions;

  @override
  State<VerifiedLeadsPage> createState() => _VerifiedLeadsPageState();
}

class _VerifiedLeadsPageState extends State<VerifiedLeadsPage> {
  late final VerifiedLeadRepository _repo = widget.repository ?? VerifiedLeadRepository();

  static const _contacted = 'contacted';

  bool get _isWhatsApp => widget.kind == VerifiedKind.whatsapp;

  /// Writes the status; the lists follow through their listeners. The
  /// snackbar shows at once — the local write already moved the lead, and a
  /// rejected write moves it back and says why.
  Future<void> _setContacted(VerifiedLead item, {required bool contacted, bool fromUndo = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(_repo.setContacted(widget.kind.collection, item.lead.id, contacted: contacted).catchError((Object _) {
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
    final kind = widget.kind;
    final signal = widget.signal;
    final icon = _isWhatsApp ? AppIcons.chat : AppIcons.mail;
    final channel = kind.title;
    return LeadCollectionPage<VerifiedLead>(
      title: '$channel · ${signal.title}',
      noun: 'business',
      headerIcon: icon,
      searchHint: 'Search ${channel.toLowerCase()} leads...',
      emptyIcon: icon,
      emptyTitle: 'No $channel leads here yet',
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
              (widget.collectionQuery ?? FirebaseFirestore.instance.collection)(kind.collection)
                  .where('sourceType', isEqualTo: signal.sourceType);
          if (category != null) q = q.where('category', isEqualTo: category);
          return q;
        }

        // Contacted: ordering by `contactedAt` also leaves out every lead that
        // has none, so this is exactly the contacted ones.
        Query<Map<String, dynamic>> contactedQuery(String? category) =>
            base(category).orderBy('contactedAt', descending: true);

        Future<int> countOf(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;

        return PagedQueryController<VerifiedLead>(
          // The list's true size, so the header says "125 businesses" and not
          // "58+" while only the first pages have loaded. New is everything
          // minus the contacted (`status` can be unset, which Firestore
          // cannot filter for).
          counter: (category) async {
            final contacted = await countOf(contactedQuery(category));
            if (contactedList) return contacted;
            final all = await countOf(base(category));
            return all > contacted ? all - contacted : 0;
          },
          segments: [
            // New: by verified date, with contacted leads dropped.
            (category) => contactedList ? contactedQuery(category) : base(category).orderBy('updatedAt', descending: true),
          ],
          map: (doc) => VerifiedLead.fromData(
            Lead.fromDoc(doc),
            doc.data(),
            _isWhatsApp ? VerifiedChannel.whatsapp : VerifiedChannel.email,
          ),
          include: contactedList ? null : (row) => !row.isContacted,
        );
      },
      // Grouped by the date each list is ordered by.
      dateOf: (row) => row.isContacted ? (row.contactedAt ?? row.shownDate) : row.shownDate,
      searchText: (r) =>
          '${r.lead.business} ${r.lead.location} ${r.lead.phone ?? ''} ${r.lead.email ?? ''} ${r.lead.category}'
              .toLowerCase(),
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
