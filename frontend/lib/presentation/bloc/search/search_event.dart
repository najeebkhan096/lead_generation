import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchSubmitted extends SearchEvent {
  const SearchSubmitted({
    required this.location,
    required this.category,
    required this.dateRange,
    this.analyze = false,
  });

  final String location;
  final String category;
  final String dateRange;
  final bool analyze;

  @override
  List<Object?> get props => [location, category, dateRange, analyze];
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
