import 'package:equatable/equatable.dart';

import '../../../domain/entities/lead.dart';
import '../../../domain/entities/lead_page.dart';

enum PagedLeadsStatus { initial, loading, success, failure }

class PagedLeadsState extends Equatable {
  const PagedLeadsState({
    this.status = PagedLeadsStatus.initial,
    this.leads = const [],
    this.nextCursor,
    this.total,
    this.query = '',
    this.category,
    this.categories = const [],
    this.verifiedOnly = false,
    this.loadingMore = false,
    this.error,
    this.deletingLeadId,
    this.deleteError,
    this.deletingCategory,
    this.categoryDeleteMessage,
  });

  final PagedLeadsStatus status;

  /// Every lead loaded so far, in order — pages are appended.
  final List<Lead> leads;

  /// `null` once the last page has been loaded.
  final String? nextCursor;

  /// Matching leads in the collection, when the server knows it.
  final int? total;

  /// Text in the search box (applied after a short debounce).
  final String query;
  final String? category;
  final List<LeadCategory> categories;
  final bool verifiedOnly;

  /// A follow-up page (or the next slice of a scanning search) is in flight.
  final bool loadingMore;
  final String? error;

  final String? deletingLeadId;
  final String? deleteError;
  final String? deletingCategory;
  final String? categoryDeleteMessage;

  bool get hasMore => nextCursor != null;
  bool get isSearching => query.trim().isNotEmpty;
  bool get hasActiveFilter =>
      isSearching || category != null || verifiedOnly;

  PagedLeadsState copyWith({
    PagedLeadsStatus? status,
    List<Lead>? leads,
    String? nextCursor,
    bool clearCursor = false,
    int? total,
    bool clearTotal = false,
    String? query,
    String? category,
    bool clearCategory = false,
    List<LeadCategory>? categories,
    bool? verifiedOnly,
    bool? loadingMore,
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
    return PagedLeadsState(
      status: status ?? this.status,
      leads: leads ?? this.leads,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      total: clearTotal ? null : (total ?? this.total),
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      categories: categories ?? this.categories,
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      loadingMore: loadingMore ?? this.loadingMore,
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
        leads,
        nextCursor,
        total,
        query,
        category,
        categories,
        verifiedOnly,
        loadingMore,
        error,
        deletingLeadId,
        deleteError,
        deletingCategory,
        categoryDeleteMessage,
      ];
}
