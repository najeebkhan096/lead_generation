import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lead.dart';
import '../models/search_batch.dart';

class LeadRepository {
  LeadRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;



  /// Real-time stream of past searches.
  Stream<List<SavedSearch>> getSearchesStream() {
    return _db.collection('searches')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(SavedSearch.fromDoc).toList());
  }

  /// Every past search batch, newest first — each saved business carries the
  /// id of the search batch that found it (`searchId`), so this is how the
  /// Saved Businesses screen offers a "filter by search" dropdown.
  Future<List<SavedSearch>> fetchSearches() async {
    final collection = _db.collection('searches');
    try {
      final snap =
          await collection.orderBy('createdAt', descending: true).limit(100).get();
      return snap.docs.map(SavedSearch.fromDoc).toList();
    } on FirebaseException {
      final snap = await collection.limit(100).get();
      return snap.docs.map(SavedSearch.fromDoc).toList();
    }
  }

  /// The categories a scan has ever been run for, newest scans first.
  ///
  /// A cheap source for the category filter: one document per scan batch,
  /// instead of reading every lead to find out which categories exist.
  Future<List<String>> fetchCategoryNames() async {
    final snap = await _db
        .collection('searches')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    final names = <String>{
      for (final doc in snap.docs)
        if (((doc.data()['category'] as String?) ?? '').trim().isNotEmpty)
          (doc.data()['category'] as String).trim(),
    };
    return names.toList()..sort();
  }

  /// Pipeline totals via server-side count aggregation — three tiny reads
  /// instead of downloading every lead to count them.
  Future<({int total, int inProgress, int won})> fetchPipelineCounts() async {
    final leads = _db.collection('leads');
    Future<int> count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;
    final results = await Future.wait([
      count(leads),
      count(leads.where('status', whereIn: ['contacted', 'booked'])),
      count(leads.where('status', isEqualTo: 'dealDone')),
    ]);
    return (total: results[0], inProgress: results[1], won: results[2]);
  }

  Future<void> updateFavorite(String leadId, bool isFavorite, String? userId) async {
    final updates = <String, dynamic>{
      'isFavorite': isFavorite,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (userId != null) {
      updates['assignedTo'] = userId;
    }
    await _db.collection('leads').doc(leadId).update(updates);
  }

  Future<void> updateStatus(String leadId, LeadStatus status, String? userId) async {
    final updates = <String, dynamic>{
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (userId != null && status != LeadStatus.lead) {
      updates['assignedTo'] = userId;
    }
    await _db.collection('leads').doc(leadId).update(updates);
  }

  Future<void> updateWhatsAppStatus(
      String leadId, bool hasWhatsApp, String? userId) async {
    final updates = <String, dynamic>{
      'hasWhatsApp': hasWhatsApp,
      'whatsAppCheckedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (userId != null) {
      updates['assignedTo'] = userId;
    }
    await _db.collection('leads').doc(leadId).update(updates);
  }

  Future<void> updateReputationStatus(
      String leadId, String status, String? userId) async {
    final updates = <String, dynamic>{
      'reputationStatus': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (userId != null) {
      updates['assignedTo'] = userId;
    }
    await _db.collection('leads').doc(leadId).update(updates);
  }
}
