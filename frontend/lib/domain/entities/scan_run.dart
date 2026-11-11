import 'package:equatable/equatable.dart';

/// A no-website scan that was stopped or cut off and can be resumed: the cities
/// it had covered are saved, so a resume only searches the rest.
class ScanRun extends Equatable {
  const ScanRun({
    required this.id,
    required this.categories,
    required this.status,
    this.coverage = 'standard',
    this.startedAt,
    this.updatedAt,
    this.citiesTotal = 0,
    this.citiesDone = 0,
    this.leads = 0,
    this.businesses = 0,
    this.percent = 0,
  });

  final String id;
  final List<String> categories;

  /// `stopped` (you stopped it) or `interrupted` (the backend went away mid-scan).
  final String status;
  final String coverage;
  final DateTime? startedAt;

  /// When progress was last saved: roughly when it stopped.
  final DateTime? updatedAt;
  final int citiesTotal;
  final int citiesDone;

  /// No-website leads found so far.
  final int leads;
  final int businesses;
  final int percent;

  bool get interrupted => status == 'interrupted';

  int get citiesLeft => (citiesTotal - citiesDone).clamp(0, citiesTotal);

  factory ScanRun.fromJson(Map<String, dynamic> json) {
    DateTime? ms(dynamic v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;
    return ScanRun(
      id: json['id'] as String,
      categories: ((json['categories'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      status: (json['status'] as String?) ?? 'stopped',
      coverage: (json['coverage'] as String?) ?? 'standard',
      startedAt: ms(json['startedAt']),
      updatedAt: ms(json['updatedAt']),
      citiesTotal: n(json['citiesTotal']),
      citiesDone: n(json['citiesDone']),
      leads: n(json['leads']),
      businesses: n(json['businesses']),
      percent: n(json['percent']),
    );
  }

  @override
  List<Object?> get props => [id, categories, status, coverage, startedAt, updatedAt, citiesTotal, citiesDone, leads, businesses, percent];
}
