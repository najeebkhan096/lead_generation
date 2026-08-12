import 'package:equatable/equatable.dart';

class WatchlistEntry extends Equatable {
  const WatchlistEntry({
    required this.id,
    required this.url,
    this.name,
    this.country = 'US',
    this.addedAt,
    this.lastScannedAt,
    this.lastRating,
    this.lastTotalReviews,
    this.lastNewReviewCount = 0,
    this.lastError,
    this.assignedTo,
    this.assignedToName,
  });

  final String id;
  final String url;
  final String? name;
  final String country;
  final DateTime? addedAt;
  final DateTime? lastScannedAt;
  final double? lastRating;
  final int? lastTotalReviews;
  final int lastNewReviewCount;
  final String? lastError;

  /// The salesman's `users/{uid}` doc id this business is assigned to, or
  /// null if unassigned.
  final String? assignedTo;
  final String? assignedToName;

  factory WatchlistEntry.fromJson(Map<String, dynamic> json) {
    return WatchlistEntry(
      id: json['id'] as String,
      url: json['url'] as String,
      name: json['name'] as String?,
      country: (json['country'] as String?) ?? 'US',
      addedAt: _parseDate(json['addedAt']),
      lastScannedAt: _parseDate(json['lastScannedAt']),
      lastRating: (json['lastRating'] as num?)?.toDouble(),
      lastTotalReviews: (json['lastTotalReviews'] as num?)?.toInt(),
      lastNewReviewCount: (json['lastNewReviewCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      assignedTo: json['assignedTo'] as String?,
      assignedToName: json['assignedToName'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  List<Object?> get props => [
        id,
        url,
        name,
        country,
        addedAt,
        lastScannedAt,
        lastRating,
        lastTotalReviews,
        lastNewReviewCount,
        lastError,
        assignedTo,
        assignedToName,
      ];
}

class WatchlistReview extends Equatable {
  const WatchlistReview({
    required this.reviewer,
    required this.text,
    required this.date,
    this.stars,
  });

  final String reviewer;
  final String text;
  final String date;
  final int? stars;

  factory WatchlistReview.fromJson(Map<String, dynamic> json) {
    return WatchlistReview(
      reviewer: (json['reviewer'] as String?) ?? 'Anonymous',
      text: (json['text'] as String?) ?? '',
      date: (json['date'] as String?) ?? 'Unknown',
      stars: (json['stars'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [reviewer, text, date, stars];
}

class WatchlistScanResult extends Equatable {
  const WatchlistScanResult({
    required this.id,
    required this.url,
    this.name,
    this.rating,
    this.totalReviews,
    this.isFirstScan = false,
    this.newReviews = const [],
    this.error,
  });

  final String id;
  final String url;
  final String? name;
  final double? rating;
  final int? totalReviews;
  final bool isFirstScan;
  final List<WatchlistReview> newReviews;
  final String? error;

  factory WatchlistScanResult.fromJson(Map<String, dynamic> json) {
    final reviewsJson = (json['newReviews'] as List<dynamic>? ?? []);
    return WatchlistScanResult(
      id: json['id'] as String,
      url: json['url'] as String,
      name: json['name'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      totalReviews: (json['totalReviews'] as num?)?.toInt(),
      isFirstScan: json['isFirstScan'] == true,
      newReviews: reviewsJson
          .map((e) => WatchlistReview.fromJson(e as Map<String, dynamic>))
          .toList(),
      error: json['error'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [id, url, name, rating, totalReviews, isFirstScan, newReviews, error];
}
