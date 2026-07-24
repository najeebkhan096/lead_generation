import 'package:equatable/equatable.dart';

import '../../../domain/entities/lead.dart';

enum SearchStatus { initial, loading, success, failure }

class SearchState extends Equatable {
  const SearchState({
    this.status = SearchStatus.initial,
    this.leads = const [],
    this.error,
    this.location = '',
    this.category = '',
    this.dateRange = '30',
    this.exportMessage,
    this.progressMessage,
    this.saveMessage,
    this.savingToDb = false,
  });

  final SearchStatus status;
  final List<Lead> leads;
  final String? error;
  final String location;
  final String category;
  final String dateRange;
  final String? exportMessage;
  final String? progressMessage;
  final String? saveMessage;
  final bool savingToDb;

  SearchState copyWith({
    SearchStatus? status,
    List<Lead>? leads,
    String? error,
    String? location,
    String? category,
    String? dateRange,
    String? exportMessage,
    String? progressMessage,
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
      dateRange: dateRange ?? this.dateRange,
      exportMessage: clearExport ? null : (exportMessage ?? this.exportMessage),
      progressMessage:
          clearProgress ? null : (progressMessage ?? this.progressMessage),
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
        dateRange,
        exportMessage,
        progressMessage,
        saveMessage,
        savingToDb,
      ];
}
