import 'package:equatable/equatable.dart';

/// One scan coverage tier: how many places it searches and roughly how long it takes.
class CoverageOption extends Equatable {
  const CoverageOption({
    required this.tier,
    required this.label,
    required this.searches,
    required this.businesses,
    required this.hours,
  });

  /// standard | extended | maximum
  final String tier;
  final String label;
  final int searches;
  final int businesses;
  final double hours;

  factory CoverageOption.fromJson(Map<String, dynamic> json) => CoverageOption(
        tier: (json['tier'] as String?) ?? 'standard',
        label: (json['label'] as String?) ?? '',
        searches: (json['searches'] as num?)?.toInt() ?? 0,
        businesses: (json['businesses'] as num?)?.toInt() ?? 0,
        hours: (json['hours'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [tier, label, searches, businesses, hours];
}
