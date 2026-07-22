import 'package:equatable/equatable.dart';

class BadReview extends Equatable {
  const BadReview({
    required this.stars,
    required this.text,
    required this.date,
    this.reviewer,
  });

  final int stars;
  final String text;
  final String date;
  final String? reviewer;

  factory BadReview.fromJson(Map<String, dynamic> json) {
    return BadReview(
      stars: (json['stars'] as num?)?.toInt() ?? 1,
      text: (json['text'] as String?) ?? '',
      date: (json['date'] as String?) ?? 'Unknown',
      reviewer: json['reviewer'] as String?,
    );
  }

  @override
  List<Object?> get props => [stars, text, date, reviewer];
}

class Lead extends Equatable {
  const Lead({
    required this.id,
    required this.business,
    required this.category,
    required this.location,
    this.address,
    this.phone,
    this.website,
    this.mapsUrl,
    this.rating,
    this.totalReviews,
    required this.badReview,
  });

  final String id;
  final String business;
  final String category;
  final String location;
  final String? address;
  final String? phone;
  final String? website;
  final String? mapsUrl;
  final double? rating;
  final int? totalReviews;
  final BadReview badReview;

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: (json['id'] as String?) ?? json['business']?.toString() ?? '',
      business: (json['business'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      website: json['website'] as String?,
      mapsUrl: json['mapsUrl'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalReviews: (json['totalReviews'] as num?)?.toInt(),
      badReview: BadReview.fromJson(
        (json['badReview'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  String get copyDetails {
    final buffer = StringBuffer()
      ..writeln(business)
      ..writeln('Category: $category')
      ..writeln('Location: $location');
    if (phone != null && phone!.isNotEmpty) buffer.writeln('Phone: $phone');
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
  List<Object?> get props => [id, business, category, location, badReview];
}
