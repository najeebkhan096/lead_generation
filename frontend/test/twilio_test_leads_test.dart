import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lead_generation_app/data/datasources/lead_remote_datasource.dart';
import 'package:lead_generation_app/data/repositories/lead_repository_impl.dart';
import 'package:lead_generation_app/domain/entities/sales_user.dart';
import 'package:lead_generation_app/domain/entities/twilio_test_lead.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/twilio_test_leads_page.dart';

/// Only the Twilio test-lead and user methods exist; anything else fails
/// loudly via [noSuchMethod].
class _FakeRepository implements LeadRepository {
  final leads = <TwilioTestLead>[];
  final created = <Map<String, String?>>[];
  final deleted = <String>[];
  bool createdNew = true;
  String? createError;

  @override
  Future<List<TwilioTestLead>> listTwilioTestLeads() async => List.of(leads);

  @override
  Future<List<SalesUser>> listUsers() async => const [
        SalesUser(id: 'u1', name: 'Sara', email: 'sara@example.com', approved: true),
        SalesUser(id: 'u2', name: 'Pending', approved: false),
      ];

  @override
  Future<TwilioTestLeadResult> createTwilioTestLead({
    required String phoneNumber,
    String name = '',
    String businessName = '',
    String? ownerId,
  }) async {
    if (createError != null) throw Exception(createError);
    created.add({'phone': phoneNumber, 'name': name, 'business': businessName, 'owner': ownerId});
    final lead = TwilioTestLead(
      id: '${ownerId}_x',
      name: name,
      businessName: businessName,
      phoneNumber: phoneNumber,
      ownerId: ownerId ?? '',
    );
    if (createdNew) leads.insert(0, lead);
    return TwilioTestLeadResult(lead: lead, created: createdNew, isTest: true);
  }

  @override
  Future<void> deleteTwilioTestLead(String id) async {
    deleted.add(id);
    leads.removeWhere((l) => l.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tall enough that the form and the list are both on screen without scrolling.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(_FakeRepository repo) => RepositoryProvider<LeadRepository>.value(
      value: repo,
      child: const MaterialApp(home: TwilioTestLeadsPage()),
    );

void main() {
  _oldBackendTests();
  testWidgets('lists existing test leads', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..leads.add(const TwilioTestLead(id: 'a', name: 'Ali', businessName: 'Cafe', phoneNumber: '+971501234567', ownerId: 'u1'));
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('+971501234567 · Sara'), findsOneWidget);
    expect(find.text('Test leads · 1'), findsOneWidget);
  });

  testWidgets('rejects a number without a country code', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '0501234567');
    await tester.tap(find.text('Add test lead'));
    await tester.pumpAndSettle();

    expect(find.text('Use international format, e.g. +971501234567'), findsOneWidget);
    expect(repo.created, isEmpty);
  });

  testWidgets('adds a lead with a normalized number and shows it in the list', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '+971 50-123 4567');
    await tester.enterText(find.widgetWithText(TextFormField, 'Business name (optional)'), 'Bakery');
    await tester.tap(find.text('Add test lead'));
    await tester.pumpAndSettle();

    expect(repo.created.single, {'phone': '+971501234567', 'name': '', 'business': 'Bakery', 'owner': ''});
    expect(find.text('Bakery'), findsOneWidget);
    expect(find.text('Test leads · 1'), findsOneWidget);
    expect(find.textContaining('Test lead added'), findsOneWidget);
  });

  testWidgets('shows the backend error and keeps the form values', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()..createError = 'Firebase is not configured';
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '+971501234567');
    await tester.tap(find.text('Add test lead'));
    await tester.pumpAndSettle();

    expect(find.text('Firebase is not configured'), findsOneWidget);
    final phone = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Phone number'));
    expect(phone.controller!.text, '+971501234567');
  });

  testWidgets('deletes a test lead', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..leads.add(const TwilioTestLead(id: 'a', name: 'Ali', businessName: '', phoneNumber: '+971501234567', ownerId: 'u1'));
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete test lead'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['a']);
    expect(find.text('No test leads yet.'), findsOneWidget);
  });
}

/// A backend started before the Twilio test routes existed answers 404 with
/// an HTML page; the page must say what to do, not just "Failed".
void _oldBackendTests() {
  testWidgets('an older backend (404 html) tells the user to restart it and stays usable', (tester) async {
    _tall(tester);
    final client = MockClient((req) async {
      if (req.url.path == '/api/users') return http.Response('{"users":[]}', 200);
      return http.Response('<!DOCTYPE html><pre>Cannot ${req.method} ${req.url.path}</pre>', 404);
    });
    final repo = LeadRepositoryImpl(LeadRemoteDataSource(client: client));
    await tester.pumpWidget(RepositoryProvider<LeadRepository>.value(
      value: repo,
      child: const MaterialApp(home: TwilioTestLeadsPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('restart it'), findsOneWidget);
    expect(find.text('Test leads'), findsOneWidget); // no misleading "· 0"

    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '+971501234567');
    await tester.tap(find.text('Add test lead'));
    await tester.pumpAndSettle();

    // Failed, but the button is usable again (not stuck on a spinner).
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).enabled, isTrue);
    expect(find.textContaining('restart it'), findsNWidgets(2));
  });
}
