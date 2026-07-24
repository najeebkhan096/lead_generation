import 'package:cloud_firestore/cloud_firestore.dart';
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

  factory BadReview.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const <String, dynamic>{};
    return BadReview(
      stars: (m['stars'] as num?)?.toInt() ?? 1,
      text: (m['text'] as String?) ?? '',
      date: (m['date'] as String?) ?? 'Unknown',
      reviewer: m['reviewer'] as String?,
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
    this.hasWhatsApp = false,
    this.waLink,
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
  final bool hasWhatsApp;
  final String? waLink;
  final BadReview badReview;

  factory Lead.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Lead(
      id: doc.id,
      business: (d['business'] as String?) ?? 'Unknown',
      category: (d['category'] as String?) ?? 'Other',
      location: (d['location'] as String?) ?? '',
      address: d['address'] as String?,
      phone: d['phone'] as String?,
      website: d['website'] as String?,
      mapsUrl: d['mapsUrl'] as String?,
      rating: (d['rating'] as num?)?.toDouble(),
      totalReviews: (d['totalReviews'] as num?)?.toInt(),
      hasWhatsApp: d['hasWhatsApp'] == true,
      waLink: d['waLink'] as String?,
      badReview: BadReview.fromMap(
        d['badReview'] as Map<String, dynamic>?,
      ),
    );
  }

  String? get whatsAppUrl {
    if (waLink != null && waLink!.trim().isNotEmpty) return waLink!.trim();
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return 'https://wa.me/$digits';
  }

  @override
  List<Object?> get props => [id, business, category, phone, mapsUrl];
}
