import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/models/lead.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}

void main() {
  group('Lead Model Tests', () {
    test('Lead.fromDoc parses fields correctly', () {
      final mockDoc = MockDocumentSnapshot();
      final data = {
        'business': 'Test Business',
        'category': 'Dentist',
        'location': 'New York',
        'isFavorite': true,
        'status': 'booked',
        'reputationStatus': 'Review removed',
      };

      when(() => mockDoc.id).thenReturn('doc_id_123');
      when(() => mockDoc.data()).thenReturn(data);

      final lead = Lead.fromDoc(mockDoc);

      expect(lead.id, 'doc_id_123');
      expect(lead.business, 'Test Business');
      expect(lead.category, 'Dentist');
      expect(lead.isFavorite, true);
      expect(lead.status, LeadStatus.booked);
      expect(lead.reputationStatus, 'Review removed');
    });

    test('Lead.fromDoc handles missing fields with defaults', () {
      final mockDoc = MockDocumentSnapshot();
      when(() => mockDoc.id).thenReturn('doc_id_456');
      when(() => mockDoc.data()).thenReturn({});

      final lead = Lead.fromDoc(mockDoc);

      expect(lead.business, 'Unknown');
      expect(lead.category, 'Other');
      expect(lead.isFavorite, false);
      expect(lead.status, LeadStatus.lead);
    });

    test('whatsAppUrl logic works', () {
      final leadWithPhone = Lead(
        id: '1',
        business: 'B',
        category: 'C',
        location: 'L',
        phone: '+1 234 567 8900',
        badReview: const BadReview(stars: 1, text: 'T', date: 'D'),
      );

      expect(leadWithPhone.whatsAppUrl, 'https://wa.me/12345678900');
    });
  });
}
