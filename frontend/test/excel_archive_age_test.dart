import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/excel_archive.dart';

ExcelArchive _archive({DateTime? scannedAt, DateTime? createdAt, String status = 'complete'}) => ExcelArchive(
      id: 'a',
      fileName: 'a.xlsx',
      downloadUrl: '',
      categories: const ['cafe'],
      scannedAt: scannedAt,
      createdAt: createdAt,
      status: status,
    );

void main() {
  test('a scan is stale from 30 days after it ran', () {
    final now = DateTime.now();
    expect(_archive(scannedAt: now.subtract(const Duration(days: 29))).isStale, isFalse);
    expect(_archive(scannedAt: now.subtract(const Duration(days: 31))).isStale, isTrue);
  });

  test('age falls back to createdAt for archives without a scan date', () {
    final old = DateTime.now().subtract(const Duration(days: 45));
    final a = _archive(createdAt: old);
    expect(a.ageDays, 45);
    expect(a.isStale, isTrue);
    expect(_archive().ageDays, isNull);
    expect(_archive().isStale, isFalse);
  });

  test('only a finished scan can be re-scanned', () {
    expect(_archive().rescannable, isTrue);
    expect(_archive(status: 'partial').rescannable, isFalse);
  });

  test('fromJson reads scannedAt', () {
    final a = ExcelArchive.fromJson({'id': 'x', 'scannedAt': '2026-09-01T00:00:00.000Z'});
    expect(a.scannedAt, DateTime.utc(2026, 9, 1));
  });
}
