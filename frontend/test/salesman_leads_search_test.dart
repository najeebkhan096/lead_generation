import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/contacted_lead.dart';
import 'package:lead_generation_app/presentation/pages/salesman_contacted_leads_page.dart';

const _acme = ContactedLead(
  id: '1',
  business: 'Acme Motors',
  category: 'automotive USA',
  location: 'Dallas, Texas',
  phone: '+12145550100',
  reviewText: 'Never showed up for the appointment',
);

void main() {
  test('an empty search matches every lead', () {
    expect(matchesLeadSearch(_acme, ''), isTrue);
    expect(matchesLeadSearch(_acme, '   '), isTrue);
  });

  test('a search finds the business, category, place, phone and review, ignoring case', () {
    expect(matchesLeadSearch(_acme, 'acme'), isTrue);
    expect(matchesLeadSearch(_acme, 'AUTOMOTIVE'), isTrue);
    expect(matchesLeadSearch(_acme, 'dallas'), isTrue);
    expect(matchesLeadSearch(_acme, '2145550100'), isTrue);
    expect(matchesLeadSearch(_acme, 'appointment'), isTrue);
  });

  test('every word must match, in any order', () {
    expect(matchesLeadSearch(_acme, 'dallas acme'), isTrue);
    expect(matchesLeadSearch(_acme, 'acme chicago'), isFalse);
  });

  test('a lead without a category or place still matches on its name', () {
    const bare = ContactedLead(id: '2', business: 'Joe Plumbing');
    expect(matchesLeadSearch(bare, 'joe'), isTrue);
    expect(matchesLeadSearch(bare, 'dallas'), isFalse);
  });
}
