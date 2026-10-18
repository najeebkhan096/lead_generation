import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/models/lead.dart';
import 'package:lead_mobile/theme/app_theme.dart';
import 'package:lead_mobile/utils/date_format.dart';
import 'package:lead_mobile/utils/lead_labels.dart';
import 'package:lead_mobile/widgets/verified_lead_card.dart';

Lead _lead({
  String business = 'Thony Automotive LLC',
  String category = 'Car Dealer USA',
  String location = 'Utah',
  String? phone = '+13857895802',
  double? rating,
  int? reviews,
  BadReview? review,
}) =>
    Lead(
      id: 'x',
      business: business,
      category: category,
      location: location,
      address: '3678 W 2150 S #1, West Valley City, UT 84120',
      phone: phone,
      mapsUrl: 'https://maps.example/x',
      rating: rating,
      totalReviews: reviews,
      badReview: review ?? const BadReview(stars: 1, text: '', date: 'Unknown'),
    );

Widget _wrap(VerifiedLead item, {LeadActions actions = const LeadActions()}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: VerifiedLeadCard(item: item, actions: actions))),
    );

void main() {
  group('formatting', () {
    test('formatTime uses a 12-hour clock', () {
      expect(formatTime(DateTime(2026, 10, 12, 15, 45)), '3:45 PM');
      expect(formatTime(DateTime(2026, 10, 12, 0, 5)), '12:05 AM');
      expect(formatTime(DateTime(2026, 10, 12, 12, 0)), '12:00 PM');
      expect(formatTime(null), isNull);
    });

    test('formatDateTime joins date and time', () {
      expect(formatDateTime(DateTime(2026, 10, 12, 15, 45)), 'Oct 12, 2026 · 3:45 PM');
      expect(formatDateTime(null), isNull);
    });

    test('cleanCategory drops the country tag', () {
      expect(cleanCategory('Car Dealer USA'), 'Car Dealer');
      expect(cleanCategory('painting service USA'), 'painting service');
      expect(cleanCategory('Cafe'), 'Cafe');
      expect(cleanCategory(''), 'Other');
    });

    test('ratingLabel', () {
      expect(ratingLabel(4.2, 118), '4.2 · 118 reviews');
      expect(ratingLabel(4.0, 1), '4.0 · 1 review');
      expect(ratingLabel(null, 5), isNull);
      expect(ratingLabel(0, 5), isNull);
    });
  });

  group('VerifiedLeadCard', () {
    testWidgets('a WhatsApp lead shows the verified date, number, place and the 1-star review', (tester) async {
      await tester.pumpWidget(_wrap(VerifiedLead(
        lead: _lead(
          rating: 3.1,
          reviews: 40,
          review: const BadReview(
            stars: 1,
            text: 'Never showed up',
            date: '2 weeks ago',
            reviewer: 'Sam',
          ),
        ),
        verifiedAt: DateTime(2026, 10, 12, 15, 45),
      )));

      expect(find.text('Thony Automotive LLC'), findsOneWidget);
      expect(find.text('Car Dealer · Utah'), findsOneWidget);
      expect(find.text('On WhatsApp · Oct 12, 2026 · 3:45 PM'), findsOneWidget);
      expect(find.text('+13857895802'), findsOneWidget);
      expect(find.text('1-star'), findsNothing); // the 1-star review is the section, not a badge
      expect(find.textContaining('3678 W 2150 S'), findsOneWidget);
      expect(find.text('3.1 · 40 reviews'), findsOneWidget);
      expect(find.text('1-star review · 2 weeks ago · by Sam'), findsOneWidget);
      expect(find.text('“Never showed up”'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'WhatsApp'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Map'), findsOneWidget);
      expect(find.byTooltip('Call'), findsNothing);
      expect(find.byTooltip('Website'), findsNothing);
      expect(find.byIcon(AppIcons.globe), findsNothing);
    });

    testWidgets('missing details are simply left out, not shown as blanks', (tester) async {
      await tester.pumpWidget(_wrap(VerifiedLead(
        lead: _lead(phone: null, location: '').copyWithNoAddress(),
      )));

      expect(find.text('Car Dealer'), findsOneWidget);
      expect(find.textContaining('On WhatsApp'), findsNothing);
      expect(find.byIcon(AppIcons.star), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Map'), findsNothing); // no map link on this lead
    });

    testWidgets('WhatsApp opens a plain chat with the lead’s number', (tester) async {
      String? opened;
      await tester.pumpWidget(_wrap(
        VerifiedLead(lead: _lead()),
        actions: LeadActions(whatsapp: (url) async {
          opened = url;
          return true;
        }),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp'));
      await tester.pump();

      expect(opened, 'https://wa.me/13857895802');
    });

    testWidgets('Map opens the lead’s map link', (tester) async {
      String? opened;
      await tester.pumpWidget(_wrap(
        VerifiedLead(lead: _lead()),
        actions: LeadActions(maps: (url) async {
          opened = url;
          return true;
        }),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'Map'));
      await tester.pump();

      expect(opened, 'https://maps.example/x');
    });

    test('shownDate prefers the verified time, then updatedAt, then createdAt', () {
      final base = _lead();
      expect(VerifiedLead(lead: base).shownDate, isNull);
      final verified = DateTime(2026, 10, 1);
      expect(VerifiedLead(lead: base, verifiedAt: verified).shownDate, verified);
    });
  });
}

extension on Lead {
  /// A copy with no address (the model has no copyWith).
  Lead copyWithNoAddress() => Lead(
        id: id,
        business: business,
        category: category,
        location: location,
        phone: phone,
        mapsUrl: null,
        badReview: badReview,
      );
}
