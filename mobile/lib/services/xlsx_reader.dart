import 'dart:typed_data';

import 'package:excel/excel.dart' as xlsx;

import '../models/excel_archive.dart';

/// Parses raw .xlsx bytes into the same {name, headers, rows} shape the
/// backend's REST `/data` endpoints return (see
/// backend/src/services/exportService.js's `xlsxBufferToJson`) — row 1 is
/// always the header row for every workbook this app produces. Runs
/// entirely on-device via the `excel` package, no network call beyond
/// whatever already fetched the bytes.
List<ExcelArchiveSheet> parseXlsxBytes(Uint8List bytes) {
  final workbook = xlsx.Excel.decodeBytes(bytes);
  final sheets = <ExcelArchiveSheet>[];

  for (final entry in workbook.tables.entries) {
    final rows = entry.value.rows;
    if (rows.isEmpty) continue;

    final headerRow = rows.first;
    final headers = headerRow.map((cell) => cell?.value?.toString().trim() ?? '').toList();

    final dataRows = <Map<String, dynamic>>[];
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      final map = <String, dynamic>{};
      var hasValue = false;
      for (var c = 0; c < headers.length; c++) {
        final header = headers[c];
        if (header.isEmpty) continue;
        final cell = c < row.length ? row[c] : null;
        final value = cell?.value?.toString() ?? '';
        map[header] = value;
        if (value.isNotEmpty) hasValue = true;
      }
      if (hasValue) dataRows.add(map);
    }

    sheets.add(ExcelArchiveSheet(
      name: entry.key,
      headers: headers.where((h) => h.isNotEmpty).toList(),
      rows: dataRows,
    ));
  }

  return sheets;
}
