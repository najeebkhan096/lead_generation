import 'package:equatable/equatable.dart';

import '../../../domain/entities/lead.dart';

enum SavedBusinessesStatus { initial, loading, success, failure }

class SavedBusinessesState extends Equatable {
  const SavedBusinessesState({
    this.status = SavedBusinessesStatus.initial,
    this.businesses = const [],
    this.query = '',
    this.error,
  });

  final SavedBusinessesStatus status;
  final List<Lead> businesses;
  final String query;
  final String? error;

  List<Lead> get filteredBusinesses {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return businesses;
    return businesses.where((lead) {
      return lead.business.toLowerCase().contains(q) ||
          (lead.phone?.toLowerCase().contains(q) ?? false) ||
          (lead.website?.toLowerCase().contains(q) ?? false) ||
          (lead.email?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  SavedBusinessesState copyWith({
    SavedBusinessesStatus? status,
    List<Lead>? businesses,
    String? query,
    String? error,
    bool clearError = false,
  }) {
    return SavedBusinessesState(
      status: status ?? this.status,
      businesses: businesses ?? this.businesses,
      query: query ?? this.query,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [status, businesses, query, error];
}
