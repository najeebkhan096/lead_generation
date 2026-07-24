import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lead.dart';

class LeadRepository {
  LeadRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const knownCategories = [
    'Restaurant',
    'Dentist',
    'Salon',
    'Hotel',
    'Car Dealer',
    'Contractor',
    'Lawyer',
  ];

  Stream<List<Lead>> watchLeads({String? category}) {
    Query<Map<String, dynamic>> query = _db.collection('leads');

    if (category != null && category.isNotEmpty && category != 'All') {
      query = query.where('category', isEqualTo: category);
    }

    // Prefer newest updates; if index missing, client still works after catch in UI.
    query = query.orderBy('updatedAt', descending: true);

    return query.snapshots().map(
          (snap) => snap.docs.map(Lead.fromDoc).toList(),
        );
  }

  Stream<List<Lead>> watchLeadsFallback({String? category}) {
    Query<Map<String, dynamic>> query = _db.collection('leads');
    if (category != null && category.isNotEmpty && category != 'All') {
      query = query.where('category', isEqualTo: category);
    }
    return query.snapshots().map(
          (snap) => snap.docs.map(Lead.fromDoc).toList(),
        );
  }
}
