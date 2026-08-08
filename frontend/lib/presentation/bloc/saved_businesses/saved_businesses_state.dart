import 'package:equatable/equatable.dart';

import '../../../domain/entities/lead.dart';

enum SavedBusinessesStatus { initial, loading, success, failure }

class SavedBusinessesState extends Equatable {
  const SavedBusinessesState({
    this.status = SavedBusinessesStatus.initial,
    this.businesses = const [],
    this.query = '',
    this.error,
    this.deletingLeadId,
    this.deleteError,
    this.deletingCategory,
    this.categoryDeleteMessage,
  });

  final SavedBusinessesStatus status;
  final List<Lead> businesses;
  final String query;
  final String? error;

  /// [Lead.dbId] currently being deleted, so its card can show a spinner —
  /// `null` when nothing is in flight.
  final String? deletingLeadId;
  final String? deleteError;

  /// Category currently being bulk-deleted — `null` when nothing is in
  /// flight.
  final String? deletingCategory;

  /// Result of the most recent bulk category delete (success or error),
  /// shown as a snackbar and then cleared.
  final String? categoryDeleteMessage;

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
    String? deletingLeadId,
    bool clearDeletingLeadId = false,
    String? deleteError,
    bool clearDeleteError = false,
    String? deletingCategory,
    bool clearDeletingCategory = false,
    String? categoryDeleteMessage,
    bool clearCategoryDeleteMessage = false,
  }) {
    return SavedBusinessesState(
      status: status ?? this.status,
      businesses: businesses ?? this.businesses,
      query: query ?? this.query,
      error: clearError ? null : (error ?? this.error),
      deletingLeadId: clearDeletingLeadId ? null : (deletingLeadId ?? this.deletingLeadId),
      deleteError: clearDeleteError ? null : (deleteError ?? this.deleteError),
      deletingCategory: clearDeletingCategory ? null : (deletingCategory ?? this.deletingCategory),
      categoryDeleteMessage:
          clearCategoryDeleteMessage ? null : (categoryDeleteMessage ?? this.categoryDeleteMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        businesses,
        query,
        error,
        deletingLeadId,
        deleteError,
        deletingCategory,
        categoryDeleteMessage,
      ];
}
