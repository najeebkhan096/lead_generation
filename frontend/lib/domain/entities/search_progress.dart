import 'package:equatable/equatable.dart';

class SearchProgress extends Equatable {
  const SearchProgress({
    this.message = '',
    this.leadCount = 0,
    this.targetCount = 100,
    this.statesDone = 0,
    this.statesTotal = 0,
    this.businessesScraped = 0,
    this.currentCategory = '',
    this.currentState = '',
  });

  final String message;
  final int leadCount;
  final int targetCount;
  final int statesDone;
  final int statesTotal;
  final int businessesScraped;
  final String currentCategory;

  /// The region/state currently being scanned (e.g. "Northern Ireland",
  /// "Texas") — empty when not searching or not yet known.
  final String currentState;

  double get leadFraction {
    if (targetCount <= 0) return 0;
    return (leadCount / targetCount).clamp(0.0, 1.0);
  }

  double? get statesFraction {
    if (statesTotal <= 0) return null;
    return (statesDone / statesTotal).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [
        message,
        leadCount,
        targetCount,
        statesDone,
        statesTotal,
        businessesScraped,
        currentCategory,
        currentState,
      ];
}
