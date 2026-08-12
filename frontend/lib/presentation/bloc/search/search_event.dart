import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchSubmitted extends SearchEvent {
  const SearchSubmitted({
    this.category,
    this.categories,
    required this.dateRange,
    this.location = 'All US states',
    this.nationwide = true,
    this.targetLeadCount = 100,
    this.analyze = false,
    this.autoSave = true,
    this.country = 'US',
  });

  final String location;
  final String? category;
  final List<String>? categories;
  final String dateRange;
  final bool nationwide;
  final int targetLeadCount;
  final bool analyze;
  final bool autoSave;
  final String country;

  @override
  List<Object?> get props => [
        location,
        category,
        categories,
        dateRange,
        nationwide,
        targetLeadCount,
        analyze,
        autoSave,
        country,
      ];
}

class SearchCleared extends SearchEvent {
  const SearchCleared();
}

class ExportCsvRequested extends SearchEvent {
  const ExportCsvRequested();
}

class ExportJsonRequested extends SearchEvent {
  const ExportJsonRequested();
}

class ExportExcelRequested extends SearchEvent {
  const ExportExcelRequested();
}

class SaveToDatabaseRequested extends SearchEvent {
  const SaveToDatabaseRequested();
}

/// Checks whether a search is already running or finished server-side (the
/// backend keeps search state in-memory only, so a page reload otherwise
/// loses all visibility into it) and resumes showing it if so.
class SearchResumeChecked extends SearchEvent {
  const SearchResumeChecked();
}
