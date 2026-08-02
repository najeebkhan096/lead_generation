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
}
