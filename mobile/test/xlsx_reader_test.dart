import 'dart:typed_data';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/services/xlsx_reader.dart';

void main() {
  test('parseXlsxBytes reads header row and data rows from a real workbook', () {
    final workbook = xlsx.Excel.createExcel();
    final sheet = workbook['Plumbers'];
    workbook.delete('Sheet1');

    sheet.appendRow([
      xlsx.TextCellValue('Business Name'),
      xlsx.TextCellValue('Phone'),
      xlsx.TextCellValue('Rating'),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Acme Plumbing'),
      xlsx.TextCellValue('+15551234567'),
      xlsx.DoubleCellValue(4.5),
    ]);
    sheet.appendRow([
      xlsx.TextCellValue('Best Pipes Co'),
      xlsx.TextCellValue('+15559876543'),
      xlsx.DoubleCellValue(3.2),
    ]);

    final bytes = Uint8List.fromList(workbook.encode()!);
    final sheets = parseXlsxBytes(bytes);

    expect(sheets, hasLength(1));
    expect(sheets.first.name, 'Plumbers');
    expect(sheets.first.headers, ['Business Name', 'Phone', 'Rating']);
    expect(sheets.first.rows, hasLength(2));
    expect(sheets.first.rows[0]['Business Name'], 'Acme Plumbing');
    expect(sheets.first.rows[0]['Phone'], '+15551234567');
    expect(sheets.first.rows[0]['Rating'], '4.5');
    expect(sheets.first.rows[1]['Business Name'], 'Best Pipes Co');
  });

  test('parseXlsxBytes skips a workbook with no data rows', () {
    final workbook = xlsx.Excel.createExcel();
    final sheet = workbook['Empty'];
    workbook.delete('Sheet1');
    sheet.appendRow([xlsx.TextCellValue('Business Name')]);

    final bytes = Uint8List.fromList(workbook.encode()!);
    final sheets = parseXlsxBytes(bytes);

    expect(sheets, hasLength(1));
    expect(sheets.first.rows, isEmpty);
  });
}
