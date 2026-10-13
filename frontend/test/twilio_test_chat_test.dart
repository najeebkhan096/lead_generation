import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_generation_app/domain/entities/twilio_test_lead.dart';
import 'package:lead_generation_app/domain/entities/twilio_test_message.dart';
import 'package:lead_generation_app/domain/repositories/lead_repository.dart';
import 'package:lead_generation_app/presentation/pages/twilio_test_chat_page.dart';
import 'package:lead_generation_app/presentation/utils/web_image_picker.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _lead = TwilioTestLead(
  id: 'L1',
  name: 'Ali',
  businessName: 'Cafe',
  phoneNumber: '+971501234567',
  ownerId: 'uid1',
);

TwilioTestMessage _msg(
  String id, {
  bool out = true,
  String body = '',
  String status = 'sent',
  String channel = 'whatsapp',
  String type = 'text',
  String? error,
}) =>
    TwilioTestMessage(
      id: id,
      isOutbound: out,
      type: type,
      channel: channel,
      body: body,
      status: status,
      errorMessage: error,
      createdAt: DateTime(2026, 10, 13, 14, 5),
    );

/// Only the chat methods exist; anything else fails loudly via [noSuchMethod].
class _FakeRepository implements LeadRepository {
  TwilioTestChat chat = const TwilioTestChat(messages: []);
  final texts = <({String body, bool sms})>[];
  final templates = <({String mime, String channel, int bytes})>[];
  final retried = <String>[];
  int syncs = 0;
  String? sendError;
  String? syncError;

  @override
  Future<TwilioTestChat> getTwilioTestChat(String leadId) async => chat;

  @override
  Future<int> syncTwilioTestChat(String leadId) async {
    syncs++;
    if (syncError != null) throw Exception(syncError);
    return 0;
  }

  @override
  Future<TwilioTestMessage> sendTwilioTestText(String leadId, {required String body, required bool sms}) async {
    if (sendError != null) throw Exception(sendError);
    texts.add((body: body, sms: sms));
    final m = _msg('n${texts.length}', body: body, channel: sms ? 'sms' : 'whatsapp', status: 'sending');
    chat = TwilioTestChat(messages: [...chat.messages, m], windowClosesAt: chat.windowClosesAt);
    return m;
  }

  @override
  Future<TwilioTestMessage> sendTwilioTestTemplate(
    String leadId, {
    required Uint8List image,
    required String mimeType,
    String channel = 'auto',
  }) async {
    templates.add((mime: mimeType, channel: channel, bytes: image.length));
    final m = _msg('t${templates.length}', type: 'template', body: 'Hello from us', status: 'sending');
    chat = TwilioTestChat(messages: [...chat.messages, m]);
    return m;
  }

  @override
  Future<TwilioTestMessage> retryTwilioTestMessage(String leadId, String messageId) async {
    retried.add(messageId);
    return _msg(messageId, status: 'sending');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(_FakeRepository repo, {ImagePicker? pickImage}) => RepositoryProvider<LeadRepository>.value(
      value: repo,
      child: MaterialApp(
        home: TwilioTestChatPage(
          lead: _lead,
          pollInterval: null,
          pickImage: pickImage ?? () async => null,
        ),
      ),
    );

void main() {
  testWidgets('shows both directions, statuses and the closed-window hint', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..chat = TwilioTestChat(messages: [
        _msg('a', body: 'hello there', status: 'delivered'),
        _msg('b', out: false, body: 'hi back'),
        _msg('c', body: 'sms ping', channel: 'sms', status: 'read'),
      ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('hi back'), findsOneWidget);
    expect(find.textContaining('Delivered'), findsOneWidget);
    expect(find.textContaining('Read'), findsOneWidget);
    expect(find.textContaining('free text is closed'), findsOneWidget);
    expect(repo.syncs, 1); // pulled from Twilio on open
  });

  testWidgets('open window says until when', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..chat = TwilioTestChat(messages: const [], windowClosesAt: DateTime.now().add(const Duration(hours: 5)));
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('free text is open until'), findsOneWidget);
    expect(find.text('No messages yet. Send one below.'), findsOneWidget);
  });

  testWidgets('sends on the selected channel and clears the field', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'first on whatsapp');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SMS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'then by sms');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(repo.texts, [(body: 'first on whatsapp', sms: false), (body: 'then by sms', sms: true)]);
    expect(find.text('then by sms'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('does not send an empty message', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(repo.texts, isEmpty);
  });

  testWidgets('shows why a send was refused and keeps the text', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..sendError = 'The 24-hour WhatsApp window is closed. Send an approved template first.';
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('The 24-hour WhatsApp window is closed. Send an approved template first.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'hello');
  });

  testWidgets('a failed message shows the reason and can be retried', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..chat = TwilioTestChat(messages: [
        _msg('bad', body: 'oops', status: 'failed', error: 'Twilio cannot send SMS to that country.'),
      ]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Twilio cannot send SMS to that country.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repo.retried, ['bad']);
  });

  testWidgets('template: picks an image, confirms the channel, then sends', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(
      repo,
      pickImage: () async => PickedImage(bytes: _png, mimeType: 'image/png', name: 'a.png'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Template + image'));
    await tester.pumpAndSettle();
    expect(find.text('Send the template?'), findsOneWidget);
    expect(find.textContaining('+971501234567'), findsWidgets);

    await tester.tap(find.text('SMS').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send').last);
    await tester.pumpAndSettle();

    expect(repo.templates, [(mime: 'image/png', channel: 'sms', bytes: _png.length)]);
    expect(find.textContaining('template + image'), findsOneWidget);
  });

  testWidgets('template: cancelling the confirmation sends nothing', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(
      repo,
      pickImage: () async => PickedImage(bytes: _png, mimeType: 'image/png', name: 'a.png'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Template + image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.templates, isEmpty);
  });

  testWidgets('template: an unusable file is explained', (tester) async {
    _tall(tester);
    final repo = _FakeRepository();
    await tester.pumpWidget(_app(
      repo,
      pickImage: () async => throw const ImagePickException('The image is larger than 5 MB.'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Template + image'));
    await tester.pumpAndSettle();

    expect(find.text('The image is larger than 5 MB.'), findsOneWidget);
    expect(repo.templates, isEmpty);
  });

  testWidgets('a Twilio lookup problem is shown without hiding the conversation', (tester) async {
    _tall(tester);
    final repo = _FakeRepository()
      ..syncError = 'Twilio is not configured on the server.'
      ..chat = TwilioTestChat(messages: [_msg('a', body: 'still here')]);
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('still here'), findsOneWidget);
    expect(find.textContaining('Twilio is not configured on the server.'), findsOneWidget);
  });
}
