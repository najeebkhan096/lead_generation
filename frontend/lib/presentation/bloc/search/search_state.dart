import 'package:equatable/equatable.dart';

import '../../../domain/entities/lead.dart';
import '../../../domain/entities/search_progress.dart';

enum SearchStatus { initial, loading, success, failure }

class SearchState extends Equatable {
  const SearchState({
    this.status = SearchStatus.initial,
    this.leads = const [],
    this.error,
    this.location = '',
    this.category = '',
    this.categories = const [],
    this.dateRange = '30',
    this.country = 'US',
    this.startedAt,
    this.exportMessage,
    this.progress,
    this.saveMessage,
    this.savingToDb = false,
  });

  final SearchStatus status;
  final List<Lead> leads;
  final String? error;
  final String location;
  final String category;
  final List<String> categories;
  final String dateRange;
  final String country;

  /// When this search session started (client-side) — used to show a live
  /// elapsed-time stat on the active-search page. On resume-after-reload
  /// this is set to the reconnect time, not the true original start, since
  /// the backend doesn't track a start timestamp itself.
  final DateTime? startedAt;
  final String? exportMessage;
  final SearchProgress? progress;
  final String? saveMessage;
  final bool savingToDb;

  SearchState copyWith({
    SearchStatus? status,
    List<Lead>? leads,
    String? error,
    String? location,
    String? category,
    List<String>? categories,
    String? dateRange,
    String? country,
    DateTime? startedAt,
    String? exportMessage,
    SearchProgress? progress,
    String? saveMessage,
    bool? savingToDb,
    bool clearError = false,
    bool clearExport = false,
    bool clearProgress = false,
    bool clearSave = false,
  }) {
    return SearchState(
      status: status ?? this.status,
      leads: leads ?? this.leads,
      error: clearError ? null : (error ?? this.error),
      location: location ?? this.location,
      category: category ?? this.category,
      categories: categories ?? this.categories,
      dateRange: dateRange ?? this.dateRange,
      country: country ?? this.country,
      startedAt: startedAt ?? this.startedAt,
      exportMessage: clearExport ? null : (exportMessage ?? this.exportMessage),
      progress: clearProgress ? null : (progress ?? this.progress),
      saveMessage: clearSave ? null : (saveMessage ?? this.saveMessage),
      savingToDb: savingToDb ?? this.savingToDb,
    );
  }

  @override
  List<Object?> get props => [
        status,
        leads,
        error,
        location,
        category,
        categories,
        dateRange,
        country,
        startedAt,
        exportMessage,
        progress,
        saveMessage,
        savingToDb,
      ];
}
