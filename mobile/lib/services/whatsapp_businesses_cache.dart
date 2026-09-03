import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// On-device snapshot of the WhatsApp Verified list. Fresh for 24 hours,
/// then the page fetches again and overwrites this file.
class CachedWhatsAppBusinesses {
  const CachedWhatsAppBusinesses({
    required this.savedAt,
    required this.salesmanId,
    required this.rows,
  });

  final DateTime savedAt;
  final String salesmanId;
  final List<Map<String, dynamic>> rows;

  bool get isFresh => DateTime.now().difference(savedAt) < const Duration(hours: 24);

  factory CachedWhatsAppBusinesses.fromJson(Map<String, dynamic> json) {
    final rowsJson = (json['rows'] as List<dynamic>? ?? []);
    return CachedWhatsAppBusinesses(
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      salesmanId: (json['salesmanId'] as String?) ?? '',
      rows: rowsJson.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'salesmanId': salesmanId,
        'rows': rows,
      };
}

class WhatsAppBusinessesCache {
  static const _fileName = 'whatsapp_verified_cache.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<CachedWhatsAppBusinesses?> read({required String salesmanId}) async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final cached = CachedWhatsAppBusinesses.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      if (cached.salesmanId != salesmanId) return null;
      return cached;
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String salesmanId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final file = await _file();
    final payload = CachedWhatsAppBusinesses(
      savedAt: DateTime.now(),
      salesmanId: salesmanId,
      rows: rows,
    );
    await file.writeAsString(jsonEncode(payload.toJson()));
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
