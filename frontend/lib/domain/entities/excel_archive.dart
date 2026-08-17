import 'package:equatable/equatable.dart';

class ExcelArchive extends Equatable {
  const ExcelArchive({
    required this.id,
    required this.fileName,
    required this.downloadUrl,
    this.categories = const [],
    this.countries = const [],
    this.totalLeads = 0,
    this.totalBusinessesProcessed = 0,
    this.status = 'complete',
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String downloadUrl;
  final List<String> categories;
  final List<String> countries;
  final int totalLeads;
  final int totalBusinessesProcessed;

  /// 'partial' — checkpointed while a scan was still running (or was
  /// interrupted before finishing); 'complete' — the scan that produced it
  /// finished normally. See multiCategoryOrchestrator.js's checkpointing.
  final String status;
  final DateTime? createdAt;

  /// Whether `/api/excel-scans/:id/resume` can pick this archive back up —
  /// any interrupted ("partial") archive, regardless of which engine made
  /// it. The backend inspects the archive itself to route to the right
  /// resume logic and reports back which live dashboard to open next (see
  /// [LeadRemoteDataSource.resumeExcelArchive]).
  bool get resumable => status == 'partial';

  factory ExcelArchive.fromJson(Map<String, dynamic> json) {
    return ExcelArchive(
      id: json['id'] as String,
      fileName: (json['fileName'] as String?) ?? '',
      downloadUrl: (json['downloadUrl'] as String?) ?? '',
      categories: ((json['categories'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      countries: ((json['countries'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      totalLeads: (json['totalLeads'] as num?)?.toInt() ?? 0,
      totalBusinessesProcessed: (json['totalBusinessesProcessed'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'complete',
      createdAt: json['createdAt'] is String && (json['createdAt'] as String).isNotEmpty
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props =>
      [id, fileName, downloadUrl, categories, countries, totalLeads, totalBusinessesProcessed, status, createdAt];
}

class ExcelArchiveSheet extends Equatable {
  const ExcelArchiveSheet({required this.name, required this.headers, required this.rows});

  final String name;
  final List<String> headers;
  final List<Map<String, dynamic>> rows;

  factory ExcelArchiveSheet.fromJson(Map<String, dynamic> json) {
    return ExcelArchiveSheet(
      name: (json['name'] as String?) ?? 'Sheet',
      headers: ((json['headers'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      rows: ((json['rows'] as List<dynamic>?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  @override
  List<Object?> get props => [name, headers, rows];
}
