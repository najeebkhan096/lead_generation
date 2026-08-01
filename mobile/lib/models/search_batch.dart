import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../utils/date_format.dart';

/// One search run (e.g. "Dentist in All US states"), as saved to Firestore's
/// `searches` collection. Every business saved from that run carries this
/// document's id in its `searchId` field, so this is how the mobile app
/// groups saved businesses by the search that found them.
class SavedSearch extends Equatable {
  const SavedSearch({
    required this.id,
    required this.category,
    required this.location,
    this.leadCount,
    this.createdAt,
  });

  final String id;
  final String category;
  final String location;
  final int? leadCount;
  final DateTime? createdAt;

  factory SavedSearch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return SavedSearch(
      id: doc.id,
      category: (d['category'] as String?) ?? 'Unknown',
      location: (d['location'] as String?) ?? '',
      leadCount: (d['leadCount'] as num?)?.toInt(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Human-readable label for dropdowns, e.g.
  /// "Dentist · All US states · 47 found · Jul 25, 2026".
  String get label {
    final date = formatDate(createdAt);
    final parts = <String>[
      category,
      if (location.isNotEmpty) location,
      if (leadCount != null) '$leadCount found',
      ?date,
    ];
    return parts.join(' · ');
  }

  @override
  List<Object?> get props => [id, category, location, leadCount, createdAt];
}
