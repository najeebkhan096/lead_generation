import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/models/lead.dart';
import 'package:lead_mobile/theme/app_theme.dart';
import 'package:lead_mobile/utils/date_format.dart';
import 'package:lead_mobile/services/open_links.dart';
import 'package:lead_mobile/utils/lead_labels.dart';
import 'package:lead_mobile/utils/outreach_email.dart';
import 'package:lead_mobile/widgets/verified_lead_card.dart';

Lead _lead({
  String business = 'Thony Automotive LLC',
  String category = 'Car Dealer USA',
  String location = 'Utah',
  String? phone = '+13857895802',
  String? email,
  String? website,
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
      email: email,
      website: website,
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
  group('outreach email', () {
    test('the body is the agreed pitch, verbatim', () {
      expect(reviewRemovalEmail().body, '''1-Star Google reviews can lower your average rating and cost your business high-value clients.

We specialize in auditing and disputing policy-violating 1-star reviews on Google Maps to get unfair bad ratings permanently taken down.

✅ No upfront cost
✅ Safe & policy-compliant process
✅ \$150 per successfully removed review (Pay only after removal)''');
    });

    test('the subject names the business when known', () {
      expect(reviewRemovalEmail(business: ' Acme ').subject, "Unfair 1-star reviews on Acme's Google listing");
      expect(reviewRemovalEmail().subject, 'Unfair 1-star reviews on your Google listing');
      expect(reviewRemovalEmail(business: '  ').subject, 'Unfair 1-star reviews on your Google listing');
    });

    test('mailtoUrl encodes spaces as %20 and line breaks as CRLF, and survives a round trip', () {
      final url = mailtoUrl('a@b.example', subject: 'Hi there & you', body: 'Line 1\n\n✅ Two');
      expect(url, startsWith('mailto:a@b.example?subject=Hi%20there%20%26%20you&body='));
      expect(url, isNot(contains('+')));
      expect(url, contains('Line%201%0D%0A%0D%0A'));
      final uri = Uri.parse(url);
      expect(uri.path, 'a@b.example');
      expect(uri.queryParameters['subject'], 'Hi there & you');
      expect(uri.queryParameters['body'], 'Line 1\r\n\r\n✅ Two');
    });

    test('no subject or body: a plain mailto', () {
      expect(mailtoUrl('a@b.example'), 'mailto:a@b.example');
      expect(mailtoUrl('a@b.example', subject: '', body: ''), 'mailto:a@b.example');
    });
  });

  group('website pitch', () {
    test('the email body is the agreed text, with the business filled in', () {
      expect(outreachEmailFor(LeadSignal.noWebsite, business: 'Acme Plumbing').body, '''Hi Acme Plumbing team,

I came across Acme Plumbing on Google Maps and wanted to reach out with an idea that could help your business grow online.

I’m a professional mobile app and web developer, helping businesses establish a strong online presence with modern websites and custom mobile applications.

I noticed your business doesn’t appear to have a website yet. A professional website can help potential customers discover your services, explore your offerings, contact you easily, and build trust in your business.

I’d love to help you bring your business online with a website tailored to your needs, or explore whether a mobile app could benefit your business.

Would you be interested? If so, I’d be happy to share some ideas tailored to your business.

Best regards,
Najeeb Khan
Mobile App & Web Developer
https://najeebportfolio.web.app''');
    });

    test('the WhatsApp text is the same, with the closing question in bold', () {
      final email = outreachEmailFor(LeadSignal.noWebsite, business: 'Acme').body;
      final whatsapp = whatsAppMessageFor(LeadSignal.noWebsite, business: 'Acme')!;
      expect(
        whatsapp,
        email.replaceFirst(
          'Would you be interested? If so, I’d be happy to share some ideas tailored to your business.',
          '*Would you be interested? If so, I’d be happy to share some ideas tailored to your business.*',
        ),
      );
    });

    test('without a business name it still reads naturally', () {
      final email = outreachEmailFor(LeadSignal.noWebsite);
      expect(email.subject, 'A professional website for your business');
      expect(email.body, startsWith('Hi there,'));
      expect(email.body, contains('I came across your business on Google Maps'));
    });

    test('a 1-star lead keeps the review pitch and an empty WhatsApp chat', () {
      expect(outreachEmailFor(LeadSignal.review, business: 'Acme').subject, "Unfair 1-star reviews on Acme's Google listing");
      expect(whatsAppMessageFor(LeadSignal.review, business: 'Acme'), isNull);
    });

    test('signalFor uses the stored signal, else the review text', () {
      expect(signalFor(sourceType: 'website', reviewText: 'bad'), LeadSignal.noWebsite);
      expect(signalFor(sourceType: 'review', reviewText: ''), LeadSignal.review);
      expect(signalFor(reviewText: 'Never showed up'), LeadSignal.review);
      expect(signalFor(reviewText: ''), LeadSignal.noWebsite);
      expect(signalFor(), LeadSignal.noWebsite);
    });

    test('whatsAppUrlWithText adds a percent-encoded text and replaces an existing one', () {
      final url = whatsAppUrlWithText('https://wa.me/13857895802', 'Hi there\nSecond line')!;
      expect(url, 'https://wa.me/13857895802?text=Hi%20there%0ASecond%20line');
      expect(whatsAppUrlWithText('https://wa.me/1385?text=old', 'new'), 'https://wa.me/1385?text=new');
      expect(whatsAppUrlWithText('https://wa.me/1385', null), 'https://wa.me/1385');
      expect(whatsAppUrlWithText(null, 'x'), isNull);
    });
  });

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

    test('hostOf, ratingLabel and emailSourceLabel', () {
      expect(hostOf('http://www.kaylorpainting.com/about'), 'kaylorpainting.com');
      expect(hostOf('joes.example'), 'joes.example');
      expect(hostOf(''), isNull);
      expect(ratingLabel(4.2, 118), '4.2 · 118 reviews');
      expect(ratingLabel(4.0, 1), '4.0 · 1 review');
      expect(ratingLabel(null, 5), isNull);
      expect(ratingLabel(0, 5), isNull);
      expect(emailSourceLabel('contact_page'), 'Contact page');
      expect(emailSourceLabel(null), 'Website');
    });
  });

  group('VerifiedLeadCard', () {
    testWidgets('a WhatsApp lead shows the verified date, number, place and the 1-star review', (tester) async {
      await tester.pumpWidget(_wrap(VerifiedLead(
        lead: _lead(
          rating: 3.1,
          reviews: 40,
          website: 'https://www.thony.example/',
          review: const BadReview(
            stars: 1,
            text: 'Never showed up',
            date: '2 weeks ago',
            reviewer: 'Sam',
          ),
        ),
        channel: VerifiedChannel.whatsapp,
        sourceType: 'review',
        verifiedAt: DateTime(2026, 10, 12, 15, 45),
      )));

      expect(find.text('Thony Automotive LLC'), findsOneWidget);
      expect(find.text('Car Dealer · Utah'), findsOneWidget);
      expect(find.text('On WhatsApp · Oct 12, 2026 · 3:45 PM'), findsOneWidget);
      expect(find.text('+13857895802'), findsOneWidget);
      expect(find.text('1-star'), findsNothing); // the signal is the section, not a badge
      expect(find.textContaining('3678 W 2150 S'), findsOneWidget);
      expect(find.text('thony.example'), findsOneWidget);
      expect(find.text('3.1 · 40 reviews'), findsOneWidget);
      expect(find.text('1-star review · 2 weeks ago · by Sam'), findsOneWidget);
      expect(find.text('“Never showed up”'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'WhatsApp'), findsOneWidget);
      expect(find.byTooltip('Call'), findsOneWidget);
      expect(find.byTooltip('Website'), findsOneWidget);
      expect(find.byTooltip('Maps'), findsOneWidget);
    });

    testWidgets('an email lead shows the address, where it was found and the extra addresses', (tester) async {
      await tester.pumpWidget(_wrap(VerifiedLead(
        lead: _lead(business: 'GSL Painting', category: 'painting service USA', location: 'Alaska', email: 'info@gslpainting.com'),
        channel: VerifiedChannel.email,
        sourceType: 'website',
        verifiedAt: DateTime(2026, 10, 13, 13, 55),
        emailSource: 'contact_page',
        emailFoundOn: 'https://www.gslpainting.com/contact',
        extraEmails: 2,
      )));

      expect(find.text('painting service · Alaska'), findsOneWidget);
      expect(find.text('Email verified · Oct 13, 2026 · 1:55 PM'), findsOneWidget);
      expect(find.textContaining('info@gslpainting.com'), findsOneWidget);
      expect(find.textContaining('+2 more'), findsOneWidget);
      expect(find.text('Found on contact page · gslpainting.com'), findsOneWidget);
      expect(find.text('No website'), findsNothing); // the signal is the section, not a badge
      expect(find.widgetWithText(FilledButton, 'Email'), findsOneWidget);
      // A no-website lead has no review block.
      expect(find.textContaining('1-star review'), findsNothing);
    });

    testWidgets('missing details are simply left out, not shown as blanks', (tester) async {
      await tester.pumpWidget(_wrap(VerifiedLead(
        lead: _lead(phone: null, location: '').copyWithNoAddress(),
        channel: VerifiedChannel.whatsapp,
      )));

      expect(find.text('Car Dealer'), findsOneWidget);
      expect(find.textContaining('On WhatsApp'), findsNothing);
      expect(find.byIcon(AppIcons.star), findsNothing);
      expect(find.byIcon(AppIcons.globe), findsNothing);
      expect(find.byTooltip('Call'), findsNothing);
    });

    testWidgets('Email opens a message to the lead, with the subject and the pitch filled in', (tester) async {
      String? sentTo;
      String? sentSubject;
      String? sentBody;
      await tester.pumpWidget(_wrap(
        VerifiedLead(
          lead: _lead(business: 'GSL Painting', email: 'info@gslpainting.com'),
          channel: VerifiedChannel.email,
          sourceType: 'review',
        ),
        actions: LeadActions(email: (address, {String? subject, String? body}) async {
          sentTo = address;
          sentSubject = subject;
          sentBody = body;
          return true;
        }),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'Email'));
      await tester.pump();

      expect(sentTo, 'info@gslpainting.com');
      expect(sentSubject, "Unfair 1-star reviews on GSL Painting's Google listing");
      expect(sentBody, startsWith('1-Star Google reviews can lower your average rating'));
      expect(sentBody, contains('✅ \$150 per successfully removed review (Pay only after removal)'));
    });

    testWidgets('a no-website lead gets the website pitch by email', (tester) async {
      String? sentSubject;
      String? sentBody;
      await tester.pumpWidget(_wrap(
        VerifiedLead(
          lead: _lead(business: 'Acme Plumbing', email: 'hello@acme.example'),
          channel: VerifiedChannel.email,
          sourceType: 'website',
        ),
        actions: LeadActions(email: (address, {String? subject, String? body}) async {
          sentSubject = subject;
          sentBody = body;
          return true;
        }),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'Email'));
      await tester.pump();

      expect(sentSubject, 'A professional website for Acme Plumbing');
      expect(sentBody, startsWith('Hi Acme Plumbing team,'));
      expect(sentBody, contains("I noticed your business doesn’t appear to have a website yet."));
      expect(sentBody, endsWith('https://najeebportfolio.web.app'));
    });

    testWidgets('a no-website lead opens WhatsApp with the website pitch typed in', (tester) async {
      String? opened;
      await tester.pumpWidget(_wrap(
        VerifiedLead(
          lead: _lead(business: 'Acme Plumbing'),
          channel: VerifiedChannel.whatsapp,
          sourceType: 'website',
        ),
        actions: LeadActions(whatsapp: (url) async {
          opened = url;
          return true;
        }),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp'));
      await tester.pump();

      final uri = Uri.parse(opened!);
      expect(uri.host, 'wa.me');
      expect(uri.path, '/13857895802');
      final text = uri.queryParameters['text']!;
      expect(text, startsWith('Hi Acme Plumbing team,'));
      expect(text, contains('*Would you be interested?'));
      expect(opened, isNot(contains('+')));
    });

    testWidgets('a 1-star lead still opens a plain WhatsApp chat', (tester) async {
      String? opened;
      await tester.pumpWidget(_wrap(
        VerifiedLead(lead: _lead(), channel: VerifiedChannel.whatsapp, sourceType: 'review'),
        actions: LeadActions(whatsapp: (url) async {
          opened = url;
          return true;
        }),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'WhatsApp'));
      await tester.pump();

      expect(opened, 'https://wa.me/13857895802');
    });

    test('shownDate prefers the verified time, then updatedAt, then createdAt', () {
      final base = _lead();
      expect(VerifiedLead(lead: base, channel: VerifiedChannel.email).shownDate, isNull);
      final verified = DateTime(2026, 10, 1);
      expect(VerifiedLead(lead: base, channel: VerifiedChannel.email, verifiedAt: verified).shownDate, verified);
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
