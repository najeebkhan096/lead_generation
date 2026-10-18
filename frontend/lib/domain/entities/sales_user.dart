import 'package:equatable/equatable.dart';

/// A mobile app account — every mobile sign-in creates one of these with
/// role `salesman` (see mobile/lib/services/auth_service.dart), used here
/// to populate "assign to salesman" pickers.
class SalesUser extends Equatable {
  const SalesUser({
    required this.id,
    required this.name,
    this.email,
    this.photoURL,
    this.role = 'salesman',
    this.approved = false,
    this.dailyLeadLimit = defaultDailyLeadLimit,
    this.createdAt,
    this.lastLoginAt,
  });

  /// New WhatsApp leads a salesman may contact per day, unless an admin set
  /// one. Matches DEFAULT_DAILY_LEAD_LIMIT on the server.
  static const defaultDailyLeadLimit = 10;

  final String id;
  final String name;
  final String? email;
  final String? photoURL;
  final String role;
  final bool approved;
  final int dailyLeadLimit;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  factory SalesUser.fromJson(Map<String, dynamic> json) {
    return SalesUser(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Unnamed',
      email: json['email'] as String?,
      photoURL: json['photoURL'] as String?,
      role: (json['role'] as String?) ?? 'salesman',
      approved: json['approved'] == true,
      dailyLeadLimit: (json['dailyLeadLimit'] as num?)?.toInt() ?? defaultDailyLeadLimit,
      createdAt: _parseDate(json['createdAt']),
      lastLoginAt: _parseDate(json['lastLoginAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  @override
  List<Object?> get props => [id, name, email, photoURL, role, approved, dailyLeadLimit, createdAt, lastLoginAt];
}
