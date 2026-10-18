import 'package:equatable/equatable.dart';

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

  /// New WhatsApp leads a salesman may contact per day, unless an admin set one.
  /// Matches DEFAULT_DAILY_LEAD_LIMIT on the server.
  static const defaultDailyLeadLimit = 10;

  final String id;
  final String name;
  final String? email;
  final String? photoURL;
  final String role; // 'admin' or 'salesman'
  final bool approved;
  final int dailyLeadLimit;
  final String? createdAt;
  final String? lastLoginAt;

  factory SalesUser.fromJson(Map<String, dynamic> json) {
    return SalesUser(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? (json['email'] as String?) ?? 'Unnamed',
      email: json['email'] as String?,
      photoURL: json['photoURL'] as String?,
      role: (json['role'] as String?) ?? 'salesman',
      approved: json['approved'] == true,
      dailyLeadLimit: (json['dailyLeadLimit'] as num?)?.toInt() ?? defaultDailyLeadLimit,
      createdAt: json['createdAt'] as String?,
      lastLoginAt: json['lastLoginAt'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, email, photoURL, role, approved, dailyLeadLimit, createdAt, lastLoginAt];
}
