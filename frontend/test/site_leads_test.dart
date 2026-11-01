import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/lead.dart';
import 'package:lead_generation_app/domain/entities/lead_page.dart';
import 'package:lead_generation_app/presentation/widgets/site_lead_card.dart';

Map<String, dynamic> _emailJson({List<Map<String, dynamic>>? emails}) => {
      'dbId': 'abc',
      'id': 'abc',
      'business': "Joe's Plumbing",
      'category': 'Plumber USA',
      'location': 'Texas',
      'phone': '+15125550100',
      'website': 'https://joes.test/',
      'email': 'info@joes.test',
      'emails': emails ??
          [
            {'address': 'info@joes.test', 'sourceUrl': 'https://www.joes.test/contact'},
            {'address': 'sales@joes.test', 'sourceUrl': 'https://www.joes.test/'},
            {'address': 'owner@gmail.com', 'sourceUrl': 'https://www.joes.test/'},
          ],
      'emailSourceUrl': 'https://www.joes.test/contact',
      'emailStatus': 'found',
      'badReview': {'stars': 1, 'text': '', 'date': 'Unknown'},
    };

/// Hosts a card at the height its page gives it (`cardExtent`), so a card that
/// outgrows its grid cell fails here as an overflow.
Widget _host(Widget child, {required double height}) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, height: height, child: child)),
    );

void main() {
  group('lead collections', () {
    test('website and email leads have their own endpoints and Firestore names', () {
      expect(LeadCollection.websiteLeads.path, '/api/db/website-leads');
      expect(LeadCollection.websiteLeads.firestoreName, 'websiteLeads');
      expect(LeadCollection.emailLeads.path, '/api/db/email-leads');
      expect(LeadCollection.emailLeads.firestoreName, 'emailLeads');
    });

    test('the existing review and WhatsApp collections are unchanged', () {
      expect(LeadCollection.reviewLeads.path, '/api/db/leads');
      expect(LeadCollection.whatsappLeads.path, '/api/db/whatsapp-leads');
    });
  });

  group('Lead parsing', () {
    test('an email lead keeps every address with its source page', () {
      final lead = Lead.fromJson(_emailJson());
      expect(lead.email, 'info@joes.test');
      expect(lead.emails.map((e) => e.address), ['info@joes.test', 'sales@joes.test', 'owner@gmail.com']);
      expect(lead.emails.first.sourceUrl, 'https://www.joes.test/contact');
      expect(lead.emailStatus, 'found');
      expect(lead.website, 'https://joes.test/');
    });

    test('a website lead carries its status; entries without an address are dropped', () {
      final lead = Lead.fromJson({
        ..._emailJson(emails: [
          {'address': '', 'sourceUrl': 'x'},
        ]),
        'websiteStatus': 'missing',
        'website': null,
      });
      expect(lead.websiteStatus, 'missing');
      expect(lead.emails, isEmpty);
    });

    test('a review lead (older payload, none of the new fields) still parses', () {
      final lead = Lead.fromJson({
        'id': 'r1',
        'business': 'Cafe',
        'category': 'Cafe USA',
        'location': 'Ohio',
        'badReview': {'stars': 1, 'text': 'cold coffee', 'date': '2 days ago'},
      });
      expect(lead.websiteStatus, isNull);
      expect(lead.email, isNull);
      expect(lead.emails, isEmpty);
      expect(lead.badReview.text, 'cold coffee');
    });

    test('copyWith keeps the email fields', () {
      final lead = Lead.fromJson(_emailJson()).copyWith(hasWhatsApp: true);
      expect(lead.emails, hasLength(3));
      expect(lead.email, 'info@joes.test');
    });
  });

  group('cards', () {
    test('shortUrl drops the scheme and www', () {
      expect(shortUrl('https://www.joes.test/contact'), 'joes.test/contact');
      expect(shortUrl('https://joes.test/'), 'joes.test');
      expect(shortUrl('not a url'), 'not a url');
    });

    testWidgets('the email card shows the business, address, source page, status, phone and location', (tester) async {
      await tester.pumpWidget(_host(EmailLeadCard(lead: Lead.fromJson(_emailJson()), onTap: () {}), height: 324));
      expect(find.text("Joe's Plumbing"), findsOneWidget);
      expect(find.text('Plumber USA'), findsOneWidget);
      expect(find.text('info@joes.test'), findsOneWidget);
      expect(find.text('sales@joes.test'), findsOneWidget);
      expect(find.text('1 more address'), findsOneWidget);
      expect(find.text('Found on joes.test/contact'), findsOneWidget);
      expect(find.text('Email found'), findsOneWidget);
      expect(find.text('+15125550100'), findsOneWidget);
      expect(find.text('Texas'), findsOneWidget);
    });

    testWidgets('the website card shows the business details and the missing-website badge', (tester) async {
      final lead = Lead.fromJson({
        'dbId': 'w1',
        'id': 'w1',
        'business': 'No Site Bakery',
        'category': 'Bakery USA',
        'location': 'Texas',
        'address': '1 Main St',
        'phone': '+15125550111',
        'mapsUrl': 'https://www.google.com/maps/place/x',
        'rating': 4.6,
        'totalReviews': 22,
        'websiteStatus': 'missing',
      });
      var tapped = 0;
      await tester.pumpWidget(_host(WebsiteLeadCard(lead: lead, onTap: () => tapped++), height: 232));
      expect(find.text('No Site Bakery'), findsOneWidget);
      expect(find.text('No website'), findsOneWidget);
      expect(find.text('4.6 · 22 reviews'), findsOneWidget);
      expect(find.text('+15125550111'), findsOneWidget);
      expect(find.text('1 Main St'), findsOneWidget);
      expect(find.text('Google Maps listing'), findsOneWidget);
      await tester.tap(find.text('No Site Bakery'));
      expect(tapped, 1);
    });
  });
}
