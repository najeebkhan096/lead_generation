import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchSubmitted extends SearchEvent {
  const SearchSubmitted({
    required this.category,
    required this.dateRange,
    this.location = 'All US states',
    this.nationwide = true,
    this.targetLeadCount = 100,
    this.analyze = false,
  });

  final String location;
  final String category;
  final String dateRange;
  final bool nationwide;
  final int targetLeadCount;
  final bool analyze;

  @override
  List<Object?> get props => [
        location,
        category,
        dateRange,
        nationwide,
        targetLeadCount,
        analyze,
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

class SaveToDatabaseRequested extends SearchEvent {
  const SaveToDatabaseRequested();
}
