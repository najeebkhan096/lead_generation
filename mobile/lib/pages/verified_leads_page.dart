import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/daily_contact_repository.dart';
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
/// Opening WhatsApp on a New lead marks it Contacted, within the salesman's
/// daily limit; "Move to New" puts it back. A banner shows today's count. When
/// the limit is reached, New leads are hidden until the next day.
class VerifiedLeadsPage extends StatefulWidget {
  const VerifiedLeadsPage({
    super.key,
    this.repository,
    this.daily,
    this.collectionQuery,
    this.actions = const LeadActions(),
  });

  /// For tests; defaults to the Firestore-backed one.
  final VerifiedLeadRepository? repository;

  /// For tests; defaults to the Firestore-backed one.
  final DailyContactRepository? daily;

  /// For tests: the query for a collection (default: Firestore's).
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;

  /// For tests: how WhatsApp / Maps are opened.
  final LeadActions actions;

  @override
  State<VerifiedLeadsPage> createState() => _VerifiedLeadsPageState();
}

class _VerifiedLeadsPageState extends State<VerifiedLeadsPage> {
  late final VerifiedLeadRepository _repo = widget.repository ?? VerifiedLeadRepository();
  late final DailyContactRepository _daily = widget.daily ?? DailyContactRepository();

  /// Today's limit and count, or null when there is no signed-in salesman.
  /// Created once, so rebuilding the page does not resubscribe.
  late final Stream<DailyContactStatus>? _today =
      _repo.currentUid == null ? null : _daily.watchToday(_repo.currentUid!);

  static const _collection = 'whatsappLeads';
  static const _sourceType = 'review';
  static const _contacted = 'contacted';

  void _say(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Saves the status through the server, which enforces the daily limit.
  /// Returns false, and says why, when it was refused. The lists follow
  /// through their listeners.
  Future<bool> _save(VerifiedLead item, {required bool contacted}) async {
    try {
      await _repo.setContacted(item.lead.id, contacted: contacted);
      return true;
    } on FirebaseFunctionsException catch (e) {
      const refused = {'resource-exhausted', 'failed-precondition', 'permission-denied'};
      _say(refused.contains(e.code) && e.message != null ? e.message! : 'Could not update the lead. Check your connection.');
    } catch (_) {
      _say('Could not update the lead. Check your connection.');
    }
    return false;
  }

  /// Moves a lead to Contacted or back to New, offering Undo after a move to
  /// Contacted.
  Future<void> _moveTo(VerifiedLead item, {required bool contacted, bool offerUndo = true}) async {
    if (!await _save(item, contacted: contacted)) return;
    _say(
      contacted ? 'Moved to Contacted' : 'Moved back to New',
      action: offerUndo ? SnackBarAction(label: 'Undo', onPressed: () => _moveTo(item, contacted: !contacted, offerUndo: false)) : null,
    );
  }

  /// Opens WhatsApp for a lead. A New lead is marked Contacted first, and if
  /// the daily limit refuses that, WhatsApp stays closed.
  Future<void> _openWhatsApp(VerifiedLead item) async {
    final isNew = !item.isContacted;
    if (isNew && !await _save(item, contacted: true)) return;
    final opened = await widget.actions.whatsapp(item.lead.whatsAppUrl);
    if (!isNew) return;
    if (!opened) {
      await _save(item, contacted: false);
      _say('Could not open WhatsApp');
      return;
    }
    _say(
      'Moved to Contacted',
      action: SnackBarAction(label: 'Undo', onPressed: () => _moveTo(item, contacted: false, offerUndo: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    if (today == null) return _list(null);
    // A pending read leaves the list as it is; a failed one says so in the
    // banner. The server still enforces the limit either way.
    return StreamBuilder<DailyContactStatus>(
      stream: today,
      builder: (context, snap) => _list(snap.data, unavailable: snap.hasError),
    );
  }

  Widget _list(DailyContactStatus? daily, {bool unavailable = false}) {
    final reached = daily?.reached ?? false;
    return LeadCollectionPage<VerifiedLead>(
      // A new key when the limit is reached, so the page starts again with
      // New hidden.
      key: ValueKey('daily-limit-reached-$reached'),
      title: 'WhatsApp · 1-star reviews',
      noun: 'business',
      headerIcon: AppIcons.chat,
      banner: daily != null
          ? _DailyBanner(status: daily)
          : unavailable
              ? const _DailyBannerUnavailable()
              : null,
      searchHint: 'Search WhatsApp leads...',
      emptyIcon: AppIcons.chat,
      emptyTitle: reached ? 'Daily limit reached' : 'No WhatsApp leads here yet',
      emptyBody: reached && daily != null
          ? 'You have contacted ${daily.used} of ${daily.limit} new leads today. New leads come back tomorrow.'
          : 'Leads you validate in the web console appear here, and move to Contacted once you reach out.',
      emptySubtitle: 'Validated leads will land here',
      filters: const [
        (label: 'New', value: null),
        (label: 'Contacted', value: _contacted),
      ],
      controllerFor: (status) {
        final contactedList = status == _contacted;
        // Today's limit reached: New leads are hidden. Contacted still shows.
        final hideNew = reached && !contactedList;
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
            if (hideNew) return 0;
            final all = await countOf(base(category));
            final contacted = await countOf(contactedByAnyone(category));
            return all > contacted ? all - contacted : 0;
          },
          segments: [
            // New: by verified date, with contacted leads dropped.
            (category) => contactedList ? myContacted(category) : base(category).orderBy('updatedAt', descending: true),
          ],
          map: (doc) => VerifiedLead.fromData(Lead.fromDoc(doc), doc.data()),
          include: contactedList ? null : (row) => !hideNew && !row.isContacted,
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
        onWhatsApp: () => _openWhatsApp(row),
        onMoveToNew: row.isContacted ? () => _moveTo(row, contacted: false) : null,
      ),
    );
  }
}

/// Shown in place of the daily count when it cannot be read.
class _DailyBannerUnavailable extends StatelessWidget {
  const _DailyBannerUnavailable();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.neutralTint,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Text(
        'Today\'s limit could not be loaded. Check your connection.',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.subtle),
      ),
    );
  }
}

/// Today's new leads contacted, against the daily limit. Becomes a notice
/// once the limit is reached.
class _DailyBanner extends StatelessWidget {
  const _DailyBanner({required this.status});

  final DailyContactStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reached = status.reached;
    final text = reached
        ? 'Daily limit reached · ${status.used} of ${status.limit} contacted today'
        : 'Today · ${status.used} of ${status.limit} contacted · ${status.left} left';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: reached ? t.accentTint : t.sageTint,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Icon(reached ? AppIcons.clock : AppIcons.circleCheck, size: 16, color: reached ? t.accentText : t.sageText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: reached ? t.accentTextStrong : t.sageTextStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
