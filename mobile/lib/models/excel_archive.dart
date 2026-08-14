import 'package:cloud_firestore/cloud_firestore.dart';

class ExcelArchive {
  const ExcelArchive({
    required this.id,
    required this.fileName,
    required this.downloadUrl,
    this.categories = const [],
    this.countries = const [],
    this.totalLeads = 0,
    this.createdAt,
  });

  final String id;
  final String fileName;
  final String downloadUrl;
  final List<String> categories;
  final List<String> countries;
  final int totalLeads;
  final DateTime? createdAt;

  factory ExcelArchive.fromJson(Map<String, dynamic> json) {
    return ExcelArchive(
      id: json['id'] as String,
      fileName: (json['fileName'] as String?) ?? '',
      downloadUrl: (json['downloadUrl'] as String?) ?? '',
      categories: ((json['categories'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      countries: ((json['countries'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      totalLeads: (json['totalLeads'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] is String && (json['createdAt'] as String).isNotEmpty
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }

  /// Reads the same `excelScans` / `whatsappValidatedScans` doc shape
  /// directly from Firestore (backend writes it via `firebase-admin/firestore`,
  /// see backend/src/services/excelArchiveStore.js) — used when fetching
  /// straight from Firebase instead of through the backend REST API.
  factory ExcelArchive.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ExcelArchive(
      id: doc.id,
      fileName: (d['fileName'] as String?) ?? '',
      downloadUrl: (d['downloadUrl'] as String?) ?? '',
      categories: ((d['categories'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      countries: ((d['countries'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      totalLeads: (d['totalLeads'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class ExcelArchiveSheet {
  const ExcelArchiveSheet({required this.name, required this.headers, required this.rows});

  final String name;
  final List<String> headers;
  final List<Map<String, dynamic>> rows;

  factory ExcelArchiveSheet.fromJson(Map<String, dynamic> json) {
    return ExcelArchiveSheet(
      name: (json['name'] as String?) ?? 'Sheet',
      headers: ((json['headers'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
      rows: ((json['rows'] as List<dynamic>?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}
