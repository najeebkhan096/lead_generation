/// First-contact messages for verified leads — what is said, per signal.
///
///  * a **1-star review** lead gets the review-removal pitch (email);
///  * a **no website** lead gets the web / mobile app pitch (email and
///    WhatsApp).
///
/// The texts are as agreed; change them here.
class OutreachEmail {
  const OutreachEmail({required this.subject, required this.body});

  final String subject;
  final String body;
}

const _body = '''1-Star Google reviews can lower your average rating and cost your business high-value clients.

We specialize in auditing and disputing policy-violating 1-star reviews on Google Maps to get unfair bad ratings permanently taken down.

✅ No upfront cost
✅ Safe & policy-compliant process
✅ \$150 per successfully removed review (Pay only after removal)''';

/// The email for [business] (named in the subject when known).
OutreachEmail reviewRemovalEmail({String? business}) {
  final name = (business ?? '').trim();
  return OutreachEmail(
    subject: name.isEmpty
        ? 'Unfair 1-star reviews on your Google listing'
        : 'Unfair 1-star reviews on $name\'s Google listing',
    body: _body,
  );
}

/// Which signal found the lead — decides the pitch.
enum LeadSignal { review, noWebsite }

/// The signal behind a verified lead: its stored `sourceType`, else (older
/// documents) a 1-star review text means a review lead — the same rule the
/// backend used when it wrote them.
LeadSignal signalFor({String? sourceType, String? reviewText}) {
  if (sourceType == 'website') return LeadSignal.noWebsite;
  if (sourceType == 'review') return LeadSignal.review;
  return (reviewText ?? '').trim().isNotEmpty ? LeadSignal.review : LeadSignal.noWebsite;
}

const _signOff = '''Najeeb Khan
Mobile App & Web Developer
https://najeebportfolio.web.app''';

/// The no-website pitch. [bold] writes the closing question in WhatsApp's
/// bold (`*…*`); plain text for email.
String _webPitch({String? business, bool bold = false}) {
  final name = (business ?? '').trim();
  final greeting = name.isEmpty ? 'Hi there,' : 'Hi $name team,';
  final found = name.isEmpty ? 'your business' : name;
  const question = 'Would you be interested? If so, I’d be happy to share some ideas tailored to your business.';
  return '''$greeting

I came across $found on Google Maps and wanted to reach out with an idea that could help your business grow online.

I’m a professional mobile app and web developer, helping businesses establish a strong online presence with modern websites and custom mobile applications.

I noticed your business doesn’t appear to have a website yet. A professional website can help potential customers discover your services, explore your offerings, contact you easily, and build trust in your business.

I’d love to help you bring your business online with a website tailored to your needs, or explore whether a mobile app could benefit your business.

${bold ? '*$question*' : question}

Best regards,
$_signOff''';
}

/// The email for a lead found by [signal].
OutreachEmail outreachEmailFor(LeadSignal signal, {String? business}) {
  switch (signal) {
    case LeadSignal.review:
      return reviewRemovalEmail(business: business);
    case LeadSignal.noWebsite:
      final name = (business ?? '').trim();
      return OutreachEmail(
        subject: name.isEmpty ? 'A professional website for your business' : 'A professional website for $name',
        body: _webPitch(business: business),
      );
  }
}

/// The WhatsApp message to prefill for a lead found by [signal], or null when
/// the chat should open empty (review leads).
String? whatsAppMessageFor(LeadSignal signal, {String? business}) {
  switch (signal) {
    case LeadSignal.review:
      return null;
    case LeadSignal.noWebsite:
      return _webPitch(business: business, bold: true);
  }
}
