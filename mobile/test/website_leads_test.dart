// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/pages/website_leads_screen.dart';
import 'package:lead_mobile/theme/app_theme.dart';
import 'package:lead_mobile/widgets/verified_lead_card.dart';

import 'support/memory_firestore.dart';

Map<String, dynamic> _site(String business, DateTime at,
        {bool whatsApp = true,
        String status = 'missing',
        String phone = '+97455500001',
        String category = 'Salon',
        List<String>? scanModes = const ['no_website']}) =>
    {
      'business': business,
      'category': category,
      'location': 'Doha',
      'phone': phone,
      'waLink': 'https://wa.me/${phone.substring(1)}',
      'websiteStatus': status,
      'hasWhatsApp': whatsApp,
      'scanModes': ?scanModes,
      'whatsAppCheckedAt': Timestamp.fromDate(at),
      'updatedAt': Timestamp.fromDate(at),
      'createdAt': Timestamp.fromDate(at),
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  final now = DateTime.now();
  final store = MemoryStore();
  late List<String> opened;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: WebsiteLeadsScreen(
          collectionQuery: (c) {
            expect(c, 'websiteLeads');
            return store.query(c);
          },
          actions: LeadActions(whatsapp: (url) async {
            opened.add('$url');
            return true;
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    opened = [];
    store.col('websiteLeads')
      ..clear()
      ..['a'] = _site('Alpha Salon', DateTime(now.year, now.month, now.day, 9))
      ..['b'] = _site('Bravo Salon', DateTime(now.year, now.month, now.day - 1), phone: '+97455500002')
      // Not validated, or has a website after all: neither belongs here.
      ..['c'] = _site('Charlie Salon', DateTime(now.year, now.month, now.day - 2), whatsApp: false, phone: '+97455500003')
      ..['d'] = _site('Delta Salon', DateTime(now.year, now.month, now.day - 3), status: 'available', phone: '+97455500004')
      // Validated, but found by a 1-star scan: another list's lead.
      ..['e'] = _site('Echo Salon', DateTime(now.year, now.month, now.day), phone: '+97455500005', scanModes: ['reviews'])
      ..['f'] = _site('Foxtrot Salon', DateTime(now.year, now.month, now.day), phone: '+97455500006', scanModes: null);
  });

  testWidgets('lists only validated no-website leads, newest first, with no review block', (tester) async {
    await pumpScreen(tester);

    expect(find.text('WhatsApp · no website'), findsOneWidget);
    expect(find.text('Alpha Salon'), findsOneWidget);
    expect(find.text('Bravo Salon'), findsOneWidget);
    expect(find.text('Charlie Salon'), findsNothing);
    expect(find.text('Delta Salon'), findsNothing);
    // Only a no-website scan's leads: a 1-star scan's side-finds (tagged or not) stay out.
    expect(find.text('Echo Salon'), findsNothing);
    expect(find.text('Foxtrot Salon'), findsNothing);
    expect(tester.getTopLeft(find.text('Alpha Salon')).dy, lessThan(tester.getTopLeft(find.text('Bravo Salon')).dy));
    expect(find.textContaining('1-star review'), findsNothing);
    expect(find.textContaining('On WhatsApp'), findsWidgets);
  });

  testWidgets('WhatsApp opens the lead\'s chat without marking anything contacted', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp').first);
    await tester.pumpAndSettle();
    expect(opened, ['https://wa.me/97455500001']);
  });

  testWidgets('says so when nothing is validated yet', (tester) async {
    store.col('websiteLeads').clear();
    await pumpScreen(tester);

    expect(find.text('No validated no-website leads yet'), findsOneWidget);
  });
}
