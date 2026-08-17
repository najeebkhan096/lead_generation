import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lead.dart';

/// Reads "website leads" — businesses discovered during a scan that have
/// no website at all — from Firestore's `websiteLeads` collection. Mirrors
/// [LeadRepository]'s shape/usage exactly (same [Lead] model, same
/// `updatedAt`-ordered stream), just pointed at the other collection: the
/// review-based `leads` flow and this one are saved by the same backend
/// scan, just filtered on opposite signals.
class WebsiteLeadRepository {
  WebsiteLeadRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// One-time fetch of every website lead, newest first.
  Future<List<Lead>> fetchAllLeads() async {
    final collection = _db.collection('websiteLeads');
    try {
      final snap =
          await collection.orderBy('updatedAt', descending: true).get();
      return snap.docs.map(Lead.fromDoc).toList();
    } on FirebaseException {
      final snap = await collection.get();
      return snap.docs.map(Lead.fromDoc).toList();
    }
  }

  /// Real-time stream of every website lead.
  Stream<List<Lead>> getLeadsStream() {
    return _db
        .collection('websiteLeads')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Lead.fromDoc).toList());
  }

  Future<void> updateFavorite(String leadId, bool isFavorite, String? userId) async {
    final updates = <String, dynamic>{
      'isFavorite': isFavorite,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (userId != null) {
      updates['assignedTo'] = userId;
    }
    await _db.collection('websiteLeads').doc(leadId).update(updates);
  }

  Future<void> updateStatus(String leadId, LeadStatus status, String? userId) async {
    final updates = <String, dynamic>{
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (userId != null && status != LeadStatus.lead) {
      updates['assignedTo'] = userId;
    }
    await _db.collection('websiteLeads').doc(leadId).update(updates);
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
    await _db.collection('websiteLeads').doc(leadId).update(updates);
  }
}
