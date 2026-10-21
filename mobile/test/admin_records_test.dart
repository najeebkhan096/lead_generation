import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/services/admin_records.dart';

void main() {
  group('client ids and names', () {
    test('the same business always gets the same id, whatever the spacing and case', () {
      expect(clientDocId('  Client   ONE '), clientDocId('client one'));
      expect(clientDocId('Client One').length, 20);
    });

    test('the id matches the backend: the first 20 hex digits of sha1 of the name key', () {
      // sha1('client one') in the backend's clientDocId.
      expect(clientDocId('Client One'), '6211b9b7578097ae134b');
    });

    test('a client needs a name', () {
      expect(() => cleanClientName('   '), throwsA(isA<AdminInputException>()));
      expect(cleanClientName('  Big   Auto  Shop '), 'Big Auto Shop');
    });
  });

  group('Google Maps links', () {
    test('a listing link is kept, with https added when missing', () {
      expect(normalizeMapsUrl('maps.app.goo.gl/abc'), 'https://maps.app.goo.gl/abc');
      expect(normalizeMapsUrl('https://www.google.com/maps/place/x'), 'https://www.google.com/maps/place/x');
      expect(normalizeMapsUrl('http://google.com/maps?q=1'), 'https://google.com/maps?q=1');
    });

    test('a website, a non-Google link, or text is refused', () {
      expect(normalizeMapsUrl('https://google.com'), isNull);
      expect(normalizeMapsUrl('https://example.com/shop'), isNull);
      expect(normalizeMapsUrl('dafaf'), isNull);
      expect(normalizeMapsUrl('maps.google.com/has space'), isNull);
      expect(normalizeMapsUrl(''), isNull);
      expect(() => requireMapsUrl('dafaf'), throwsA(isA<AdminInputException>()));
    });
  });

  group('input the admin sends', () {
    test('an unknown stage is refused with the list of stages', () {
      expect(
        () => saleFields({'leadStatus': 'shipped'}),
        throwsA(predicate((e) => e is AdminInputException && e.message.contains('new, in_progress'))),
      );
    });

    test('money is read as the backend reads it: numbers, numeric text, or 0', () {
      final f = saleFields({'priceChargedToClient': '12.5', 'removalCost': 'abc', 'employeePaymentAmount': 40});
      expect(f['priceChargedToClient'], 12.5);
      expect(f['removalCost'], 0);
      expect(f['employeePaymentAmount'], 40.0);
    });

    test('a new sale needs a business name and starts at the backend defaults', () {
      expect(() => newSaleDocument({'businessName': '  '}), throwsA(isA<AdminInputException>()));
      final doc = newSaleDocument({'businessName': ' Alpha ', 'paymentsArchived': true});
      expect(doc['businessName'], 'Alpha');
      expect(doc['leadStatus'], 'new');
      expect(doc['clientPaymentStatus'], 'pending');
      expect(doc['employeePaymentStatus'], 'pending');
      expect(doc['paymentsArchived'], isFalse); // a new sale is never born archived
      expect(doc.containsKey('paymentsArchivedAt'), isFalse);
    });

    test('a daily limit is 0 to 1000, or null for the default', () {
      checkDailyLeadLimit(null);
      checkDailyLeadLimit(0);
      checkDailyLeadLimit(1000);
      expect(() => checkDailyLeadLimit(1001), throwsA(isA<AdminInputException>()));
      expect(() => checkDailyLeadLimit(-1), throwsA(isA<AdminInputException>()));
    });

    test('a role is admin or salesman', () {
      checkRole('admin');
      checkRole('salesman');
      expect(() => checkRole('boss'), throwsA(isA<AdminInputException>()));
    });
  });

  group('records as the admin screens read them', () {
    test('a sale keeps its money and turns dates into ISO text', () {
      final when = Timestamp.fromDate(DateTime.utc(2026, 10, 1, 9));
      final json = saleJson('s1', {
        'businessName': 'Alpha',
        'leadStatus': 'shipped', // not a stage: shown as new
        'priceChargedToClient': 150,
        'clientAmountReceived': 500.5,
        'createdAt': when,
      });
      expect(json['leadStatus'], 'new');
      expect(json['priceChargedToClient'], 150.0);
      expect(json['clientAmountReceived'], 500.5);
      expect(json['createdAt'], '2026-10-01T09:00:00.000Z');
      expect(json['updatedAt'], isNull);
    });

    test('a salesman with no name shows their email, then Unnamed', () {
      expect(userJson('u1', {'email': 'a@b.c'})['name'], 'a@b.c');
      expect(userJson('u2', {})['name'], 'Unnamed');
      expect(userJson('u3', {})['dailyLeadLimit'], 10);
      expect(userJson('u4', {'dailyLeadLimit': 4})['dailyLeadLimit'], 4);
    });

    test('a client keeps its name and link', () {
      final json = clientJson('c1', {'businessName': 'Client One', 'mapsUrl': 'https://maps.app.goo.gl/x'});
      expect(json['businessName'], 'Client One');
      expect(json['mapsUrl'], 'https://maps.app.goo.gl/x');
    });
  });

  group('the fresh start', () {
    final sales = <Map<String, dynamic>>[
      {'id': 'old', 'createdAt': '2026-01-05T00:00:00.000Z', 'paymentsArchived': false},
      {'id': 'new', 'createdAt': '2026-10-10T00:00:00.000Z', 'paymentsArchived': false},
      {'id': 'undated', 'createdAt': null, 'paymentsArchived': false},
      {'id': 'done', 'createdAt': '2026-02-01T00:00:00.000Z', 'paymentsArchived': true},
    ];

    test('archives sales created before the date, and undated ones, not archived yet', () {
      final ids = selectForArchive(sales, before: DateTime.utc(2026, 10, 1)).map((s) => s['id']);
      expect(ids, ['old', 'undated']);
    });

    test('restore undoes the archive for old archived sales only', () {
      final ids = selectForArchive(sales, before: DateTime.utc(2026, 10, 1), restore: true).map((s) => s['id']);
      expect(ids, ['done']);
    });

    test('with no date, every sale not archived yet is a target', () {
      final ids = selectForArchive(sales).map((s) => s['id']);
      expect(ids, ['old', 'new', 'undated']);
    });
  });
}
