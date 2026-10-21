import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lead.dart';
import '../services/verified_lead_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/verified_lead_card.dart';
import 'verified_lead_detail_page.dart';

/// The deals this salesman has closed: the WhatsApp leads they contacted and
/// marked a deal done, newest deal first. Live, so a deal marked on its detail
/// page shows here at once, and a reopened one leaves.
class DealsPage extends StatefulWidget {
  const DealsPage({
    super.key,
    this.repository,
    this.collectionQuery,
    this.uid,
    this.actions = const LeadActions(),
  });

  /// For tests; defaults to the Firestore-backed one.
  final VerifiedLeadRepository? repository;

  /// For tests: the query for a collection (default: Firestore's).
  final Query<Map<String, dynamic>> Function(String collection)? collectionQuery;

  /// For tests; defaults to the signed-in salesman.
  final String? uid;

  /// For tests: how WhatsApp / Maps are opened.
  final LeadActions actions;

  @override
  State<DealsPage> createState() => _DealsPageState();
}

class _DealsPageState extends State<DealsPage> {
  late final VerifiedLeadRepository _repo = widget.repository ?? VerifiedLeadRepository();
  Stream<List<VerifiedLead>>? _deals;

  @override
  void initState() {
    super.initState();
    final uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final leads = (widget.collectionQuery ?? FirebaseFirestore.instance.collection)('whatsappLeads');
    // Equality filters only, so no composite index is needed; newest first is sorted here.
    _deals = leads
        .where('sourceType', isEqualTo: 'review')
        .where('contactedBy', isEqualTo: uid)
        .where('status', isEqualTo: 'dealDone')
        .snapshots()
        .map((snap) => [for (final doc in snap.docs) VerifiedLead.fromData(Lead.fromDoc(doc), doc.data())]
          ..sort((a, b) => _doneAt(b).compareTo(_doneAt(a))));
  }

  static DateTime _doneAt(VerifiedLead d) => d.dealDoneAt ?? d.contactedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  void _open(VerifiedLead row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VerifiedLeadDetailPage(
          item: row,
          actions: widget.actions,
          onDealDone: (done) => runLeadWrite(context, () => _repo.setDealDone(row.lead.id, done: done)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final deals = _deals;
    if (deals == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('Sign in to see your deals.'))),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<VerifiedLead>>(
          stream: deals,
          builder: (context, snapshot) {
            final list = snapshot.data;
            final String subtitle;
            if (snapshot.hasError) {
              subtitle = 'Could not load your deals';
            } else if (list == null) {
              subtitle = 'Loading…';
            } else if (list.isEmpty) {
              subtitle = 'Deals you mark as done show up here';
            } else {
              subtitle = '${list.length} ${list.length == 1 ? 'deal' : 'deals'} done';
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: 'Deals',
                  subtitle: subtitle,
                  trailing: HeaderBadge(icon: AppIcons.handshake, background: t.sageTint, foreground: t.sageDeep),
                ),
                Expanded(child: _body(snapshot, list)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(AsyncSnapshot<List<VerifiedLead>> snapshot, List<VerifiedLead>? list) {
    if (snapshot.hasError) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Could not load your deals. Check your connection.', textAlign: TextAlign.center),
      ));
    }
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Open a contacted lead and mark it a deal done. It will land here.',
          textAlign: TextAlign.center,
        ),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final row = list[i];
        return VerifiedLeadCard(
          key: ValueKey(row.lead.id),
          item: row,
          actions: widget.actions,
          onOpen: () => _open(row),
        );
      },
    );
  }
}
