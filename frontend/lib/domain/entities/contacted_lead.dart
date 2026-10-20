/// A 1-star WhatsApp lead one salesman has contacted, as the admin sees it.
class ContactedLead {
  const ContactedLead({
    required this.id,
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

  /// The Firestore id of the `whatsappLeads` document.
  final String id;
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
