/// A lead one salesman has contacted — a 1-star WhatsApp lead or a no-website
/// lead — as the admin sees it.
class ContactedLead {
  const ContactedLead({
    required this.id,
    this.kind = 'review',
    required this.business,
    this.category,
    this.location,
    this.phone,
    this.rating,
    this.totalReviews,
    this.status = 'contacted',
    this.contactedAt,
    this.reviewText = '',
    this.mapsUrl,
  });

  /// The Firestore id of the `whatsappLeads` (1-star) or `websiteLeads` document.
  final String id;

  /// `review` (1-star) or `website` (no website).
  final String kind;

  bool get isWebsite => kind == 'website';

  /// Unique across both collections: a business can be a lead of both kinds, and
  /// the two documents share an id.
  String get key => '$kind/$id';
  final String business;
  final String? category;
  final String? location;
  final String? phone;
  final double? rating;
  final int? totalReviews;
  final String status;
  final DateTime? contactedAt;

  /// The 1-star review that made the business a lead.
  final String reviewText;

  /// The business's Google Maps listing, if known.
  final String? mapsUrl;

  factory ContactedLead.fromJson(Map<String, dynamic> json) {
    return ContactedLead(
      id: (json['id'] as String?) ?? '',
      kind: (json['kind'] as String?) == 'website' ? 'website' : 'review',
      business: (json['business'] as String?) ?? 'Unnamed',
      category: json['category'] as String?,
      location: json['location'] as String?,
      phone: json['phone'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalReviews: (json['totalReviews'] as num?)?.toInt(),
      status: (json['status'] as String?) ?? 'contacted',
      contactedAt: json['contactedAt'] is String
          ? DateTime.tryParse(json['contactedAt'] as String)?.toLocal()
          : null,
      reviewText: (json['reviewText'] as String?) ?? '',
      mapsUrl: json['mapsUrl'] as String?,
    );
  }
}
