import 'package:equatable/equatable.dart';

/// A lead created from the Twilio test page (`outreachLeads/{id}` with
/// `isTest: true`) — the same document the mobile Outreach inbox shows.
class TwilioTestLead extends Equatable {
  const TwilioTestLead({
    required this.id,
    required this.name,
    required this.businessName,
    required this.phoneNumber,
    required this.ownerId,
    this.createdAt,
  });

  final String id;
  final String name;
  final String businessName;

  /// E.164, e.g. +971501234567.
  final String phoneNumber;

  /// Firebase uid of the mobile user whose inbox shows this lead.
  final String ownerId;
  final DateTime? createdAt;

  factory TwilioTestLead.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    return TwilioTestLead(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      businessName: (json['businessName'] as String?) ?? '',
      phoneNumber: (json['phoneNumber'] as String?) ?? '',
      ownerId: (json['ownerId'] as String?) ?? '',
      createdAt: created is num ? DateTime.fromMillisecondsSinceEpoch(created.toInt()) : null,
    );
  }

  @override
  List<Object?> get props => [id, name, businessName, phoneNumber, ownerId, createdAt];
}

/// Outcome of adding a test lead. [created] is false when the owner already
/// had a lead for that number; [isTest] is false when that lead is a real
/// one (it is left untouched and cannot be deleted from the test page).
class TwilioTestLeadResult extends Equatable {
  const TwilioTestLeadResult({required this.lead, required this.created, required this.isTest});

  final TwilioTestLead lead;
  final bool created;
  final bool isTest;

  factory TwilioTestLeadResult.fromJson(Map<String, dynamic> json) => TwilioTestLeadResult(
        lead: TwilioTestLead.fromJson(json['lead'] as Map<String, dynamic>),
        created: json['created'] == true,
        isTest: json['isTest'] == true,
      );

  @override
  List<Object?> get props => [lead, created, isTest];
}
