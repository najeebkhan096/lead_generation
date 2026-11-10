import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/presentation/widgets/lead_table.dart';

Lead _lead({
  String business = 'Lone Star Plumbing',
  String? phone = '+1 512 555 0100',
  String? email,
  List<LeadEmail> emails = const [],
  double? rating = 3.4,
  bool whatsapp = false,
  DateTime? saved,
}) =>
    Lead(
      id: 'x',
      dbId: 'db-x',
      business: business,
      category: 'Plumber',
      location: 'Houston, TX',
      address: '1 Main St, Houston',
      phone: phone,
      rating: rating,
      totalReviews: 120,
      hasWhatsApp: whatsapp,
      badReview: const BadReview(stars: 1, text: 'Late, rude, and "never again"', date: '2 weeks ago'),
      savedAt: saved ?? DateTime.utc(2026, 11, 9),
      email: email,
      emails: emails,
    );

/// The CSV text after its UTF-8 byte-order mark (which `utf8.decode` would swallow silently).
String _csv(List<int> bytes) {
  expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM so Excel reads accents correctly');
  return utf8.decode(bytes.sublist(3));
}

List<List<String>> _parse(String csv) {
  // A small CSV reader for the quoting rules the exporter uses.
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < csv.length; i++) {
    final c = csv[i];
    if (quoted) {
      if (c == '"' && i + 1 < csv.length && csv[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = [];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}

/// The exporter's output as rows of cells (header first).
List<List<String>> _rowsOf(List<Lead> leads) => _parse(_csv(leadsToCsv(leads)));

void main() {
  group('leadsToCsv', () {
    test('starts with a BOM so Excel reads UTF-8, then a header and one row per lead', () {
      final rows = _rowsOf([_lead(), _lead(business: 'Bluebonnet Dental')]);
      expect(rows.length, 3);
      expect(rows.first, contains('Business'));
      expect(rows.first, contains('Emails'));
      expect(rows[1][0], 'Lone Star Plumbing');
      expect(rows[2][0], 'Bluebonnet Dental');
    });

    test('keeps commas, quotes and newlines inside their cell', () {
      final rows = _rowsOf([_lead(business: 'Smith, Jones & "Sons"\nLtd')]);
      expect(rows[1][0], 'Smith, Jones & "Sons"\nLtd');
      expect(rows[1][rows.first.indexOf('Latest 1-star review')], 'Late, rude, and "never again"');
    });

    test('includes every address and its source page, preserving multiple emails', () {
      final lead = _lead(emails: const [
        LeadEmail(address: 'hello@lonestar.com', sourceUrl: 'https://lonestar.com/contact'),
        LeadEmail(address: 'info@lonestar.com'),
      ]);
      final rows = _rowsOf([lead]);
      final header = rows.first;
      expect(rows[1][header.indexOf('Emails')], 'hello@lonestar.com; info@lonestar.com');
      expect(rows[1][header.indexOf('Email source')], 'https://lonestar.com/contact');
    });

    test('falls back to the single headline email and never invents one', () {
      final withHeadline = _rowsOf([_lead(email: 'a@b.co')]);
      expect(withHeadline[1][withHeadline.first.indexOf('Emails')], 'a@b.co');

      final none = _rowsOf([_lead()]);
      expect(none[1][none.first.indexOf('Emails')], isEmpty);
    });

    test('exports business, rating, WhatsApp state and date', () {
      final rows = _rowsOf([_lead(whatsapp: true)]);
      final h = rows.first;
      expect(rows[1][h.indexOf('Phone')], '+1 512 555 0100');
      expect(rows[1][h.indexOf('Rating')], '3.4');
      expect(rows[1][h.indexOf('Reviews')], '120');
      expect(rows[1][h.indexOf('On WhatsApp')], 'Yes');
      expect(rows[1][h.indexOf('Added')], startsWith('2026-11-09'));
    });

    test('an empty list is just the header', () {
      expect(_rowsOf(const []).length, 1);
    });
  });

  group('leadComparator', () {
    final a = _lead(business: 'alpha', rating: 2.0, saved: DateTime.utc(2026, 1, 1));
    final b = _lead(business: 'Beta', rating: 4.5, saved: DateTime.utc(2026, 6, 1));

    test('sorts by business case-insensitively', () => expect(leadComparator('Business')!(a, b), lessThan(0)));
    test('sorts by rating', () => expect(leadComparator('Rating')!(a, b), lessThan(0)));
    test('sorts by date added', () => expect(leadComparator('Added')!(b, a), greaterThan(0)));
    test('columns without a sort order return null', () => expect(leadComparator('Phone'), isNull));
  });

  test('leadEmails prefers the full list over the headline address', () {
    expect(leadEmails(_lead()), isEmpty);
    expect(leadEmails(_lead(email: 'a@b.co')).single.address, 'a@b.co');
    expect(leadEmails(_lead(email: 'a@b.co', emails: const [LeadEmail(address: 'x@y.co'), LeadEmail(address: 'z@y.co')])).length, 2);
  });
}
