import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lead.dart';
import '../models/search_batch.dart';

class LeadRepository {
  LeadRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// One-time fetch of every saved business, newest first.
  ///
  /// Falls back to an unordered fetch if the `updatedAt` index/field is
  /// unavailable so the Saved Businesses screen still loads.
  Future<List<Lead>> fetchAllLeads() async {
    final collection = _db.collection('leads');
    try {
      final snap =
          await collection.orderBy('updatedAt', descending: true).get();
      return snap.docs.map(Lead.fromDoc).toList();
    } on FirebaseException {
      final snap = await collection.get();
      return snap.docs.map(Lead.fromDoc).toList();
    }
  }

  /// Real-time stream of every saved business.
  Stream<List<Lead>> getLeadsStream() {
    return _db.collection('leads')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Lead.fromDoc).toList());
  }

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
