import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/excel_archive.dart';
import 'xlsx_reader.dart';

/// Reads Excel-scan and WhatsApp-verified archives straight from Firebase —
/// Firestore for the metadata list, a plain HTTP GET against the pre-signed
/// Storage `downloadUrl` (already authorized by its own signature, no auth
/// header needed) for the workbook bytes, parsed on-device. Deliberately
/// bypasses the backend Express server entirely: that server only runs on
/// the desktop Launcher's machine, so a phone off that network could never
/// reach it, while Firebase is reachable from anywhere.
class ArchiveRepository {
  ArchiveRepository({FirebaseFirestore? firestore, http.Client? client})
      : _db = firestore ?? FirebaseFirestore.instance,
        _client = client ?? http.Client();

  final FirebaseFirestore _db;
  final http.Client _client;

  Future<List<ExcelArchive>> listExcelScans() => _list('excelScans');

  Future<List<ExcelArchive>> listValidatedScans() => _list('whatsappValidatedScans');

  Future<List<ExcelArchive>> _list(String collection) async {
    final snap = await _db.collection(collection).orderBy('createdAt', descending: true).get();
    return snap.docs.map(ExcelArchive.fromDoc).toList();
  }

  /// Downloads and parses one archive's workbook on-device.
  Future<List<ExcelArchiveSheet>> fetchSheets(ExcelArchive archive) async {
    final response = await _client.get(Uri.parse(archive.downloadUrl));
    if (response.statusCode >= 400) {
      throw Exception('Failed to download archive (HTTP ${response.statusCode})');
    }
    return parseXlsxBytes(response.bodyBytes);
  }
}
