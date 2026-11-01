import 'package:equatable/equatable.dart';

class BadReview extends Equatable {
  const BadReview({
    required this.stars,
    required this.text,
    required this.date,
    this.reviewer,
    this.link,
  });

  final int stars;
  final String text;
  final String date;
  final String? reviewer;
  final String? link;

  factory BadReview.fromJson(Map<String, dynamic> json) {
    return BadReview(
      stars: (json['stars'] as num?)?.toInt() ?? 1,
      text: (json['text'] as String?) ?? '',
      date: (json['date'] as String?) ?? 'Unknown',
      reviewer: json['reviewer'] as String?,
      link: json['link'] as String?,
    );
  }

  @override
  List<Object?> get props => [stars, text, date, reviewer, link];
}

/// One email address a business's website publishes, and the page it was
/// read from.
class LeadEmail extends Equatable {
  const LeadEmail({required this.address, this.sourceUrl});

  final String address;

  /// The page the address was found on — so a result can be traced back.
  final String? sourceUrl;

  factory LeadEmail.fromJson(Map<String, dynamic> json) => LeadEmail(
        address: (json['address'] as String?) ?? '',
        sourceUrl: json['sourceUrl'] as String?,
      );

  @override
  List<Object?> get props => [address, sourceUrl];
}

/// A business with a recent 1-star review (see the scan), optionally verified
/// on WhatsApp.
class Lead extends Equatable {
  const Lead({
    required this.id,
    this.dbId,
    required this.business,
    required this.category,
    required this.location,
    this.address,
    this.phone,
    this.website,
    this.mapsUrl,
    this.rating,
    this.totalReviews,
    this.hasWhatsApp = false,
    this.waLink,
    required this.badReview,
    this.savedAt,
    this.whatsAppCheckedAt,
    this.websiteStatus,
    this.email,
    this.emails = const [],
    this.emailStatus,
    this.emailSourceUrl,
  });

  final String id;

  /// The Firestore document id. Not always the same as [id] (which may be
  /// an externalId from the original scrape) — this is the one to send
  /// back for anything that writes to this lead's doc, like WhatsApp
  /// validation.
  final String? dbId;
  final String business;
  final String category;
  final String location;
  final String? address;
  final String? phone;
  final String? website;
  final String? mapsUrl;
  final double? rating;
  final int? totalReviews;

  /// True once a real WhatsApp Web check has confirmed this number is
  /// registered — not just "has a phone number that might work".
  final bool hasWhatsApp;
  final String? waLink;
  final BadReview badReview;
  final DateTime? savedAt;

  /// When [hasWhatsApp] was last determined by an actual check. `null`
  /// means it's never been checked (unverified, not "not on WhatsApp").
  final DateTime? whatsAppCheckedAt;

  /// Website leads only: `missing` for a business confirmed to have no
  /// website. `null` on review leads.
  final String? websiteStatus;

  /// Email leads only: the headline address, every address found, the
  /// extraction status (`found`) and the page the headline address came from.
  final String? email;
  final List<LeadEmail> emails;
  final String? emailStatus;
  final String? emailSourceUrl;

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: (json['id'] as String?) ?? json['business']?.toString() ?? '',
      dbId: json['dbId'] as String?,
      business: (json['business'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      website: json['website'] as String?,
      mapsUrl: json['mapsUrl'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalReviews: (json['totalReviews'] as num?)?.toInt(),
      hasWhatsApp: json['hasWhatsApp'] == true,
      waLink: json['waLink'] as String?,
      badReview: BadReview.fromJson(
        (json['badReview'] as Map<String, dynamic>?) ?? const {},
      ),
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? ''),
      whatsAppCheckedAt: DateTime.tryParse((json['whatsAppCheckedAt'] as String?) ?? ''),
      websiteStatus: json['websiteStatus'] as String?,
      email: json['email'] as String?,
      emails: ((json['emails'] as List<dynamic>?) ?? const [])
          .map((e) => LeadEmail.fromJson(e as Map<String, dynamic>))
          .where((e) => e.address.isNotEmpty)
          .toList(),
      emailStatus: json['emailStatus'] as String?,
      emailSourceUrl: json['emailSourceUrl'] as String?,
    );
  }

  Lead copyWith({
    bool? hasWhatsApp,
    DateTime? whatsAppCheckedAt,
  }) {
    return Lead(
      id: id,
      dbId: dbId,
      business: business,
      category: category,
      location: location,
      address: address,
      phone: phone,
      website: website,
      mapsUrl: mapsUrl,
      rating: rating,
      totalReviews: totalReviews,
      hasWhatsApp: hasWhatsApp ?? this.hasWhatsApp,
      waLink: waLink,
      badReview: badReview,
      savedAt: savedAt,
      whatsAppCheckedAt: whatsAppCheckedAt ?? this.whatsAppCheckedAt,
      websiteStatus: websiteStatus,
      email: email,
      emails: emails,
      emailStatus: emailStatus,
      emailSourceUrl: emailSourceUrl,
    );
  }

  String get copyDetails {
    final buffer = StringBuffer()
      ..writeln(business)
      ..writeln('Category: $category')
      ..writeln('Location: $location');
    if (phone != null && phone!.isNotEmpty) buffer.writeln('Phone: $phone');
    if (waLink != null && waLink!.isNotEmpty) {
      buffer.writeln('WhatsApp: $waLink');
    }
    if (website != null && website!.isNotEmpty) {
      buffer.writeln('Website: $website');
    }
    if (mapsUrl != null && mapsUrl!.isNotEmpty) {
      buffer.writeln('Maps: $mapsUrl');
    }
    buffer
      ..writeln('Rating: ${rating ?? 'N/A'}')
      ..writeln('1-star review (${badReview.date}): ${badReview.text}');
    return buffer.toString();
  }

  @override
  List<Object?> get props => [id, business, category, location, hasWhatsApp, waLink, badReview];
}
