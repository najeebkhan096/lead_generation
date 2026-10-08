import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? tsToDate(Object? v) => v is Timestamp ? v.toDate() : null;

/// `outreachLeads/{leadId}` — leadId == conversationId == `<uid>_<phone digits>`.
class OutreachLead {
  final String id;
  final String name;
  final String businessName;
  final String phoneNumber; // E.164
  final String? profileImage;
  final DateTime createdAt;
  final String lastMessage; // already a preview: text, "📷 Photo", ...
  final String? lastMessageType;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// Extra facts about the business (category, address, rating, ...).
  final Map<String, String> details;

  const OutreachLead({
    required this.id,
    required this.name,
    required this.businessName,
    required this.phoneNumber,
    this.profileImage,
    required this.createdAt,
    this.lastMessage = '',
    this.lastMessageType,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.details = const {},
  });

  /// What the list sorts on: last activity, else creation time.
  DateTime get activityAt => lastMessageAt ?? createdAt;

  /// Business name first; falls back to the contact name, then the number.
  String get displayName {
    if (businessName.trim().isNotEmpty) return businessName.trim();
    return name.trim().isNotEmpty ? name.trim() : phoneNumber;
  }

  String get initial {
    final s = displayName;
    return String.fromCharCode(s.runes.first).toUpperCase();
  }

  factory OutreachLead.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return OutreachLead(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      businessName: (d['businessName'] ?? '').toString(),
      phoneNumber: (d['phoneNumber'] ?? '').toString(),
      profileImage: d['profileImage'] as String?,
      createdAt: tsToDate(d['createdAt']) ?? DateTime.now(),
      lastMessage: (d['lastMessage'] ?? '').toString(),
      lastMessageType: d['lastMessageType'] as String?,
      lastMessageAt: tsToDate(d['lastMessageAt']),
      unreadCount: (d['unreadCount'] as num?)?.toInt() ?? 0,
      details: {
        for (final e in (d['details'] is Map ? d['details'] as Map : const {}).entries)
          e.key.toString(): e.value.toString(),
      },
    );
  }
}

/// `outreachConversations/{id}` — only what the UI needs: the 24h window.
class OutreachConversation {
  final DateTime? lastInboundAt;
  const OutreachConversation({this.lastInboundAt});

  static const window = Duration(hours: 24);

  /// WhatsApp customer-service window: freeform messages only within 24h of the
  /// lead's last inbound message. Twilio exposes no state for this, so it is
  /// derived from our persisted inbound timestamps (the backend enforces it too).
  bool isWindowOpen([DateTime? now]) =>
      lastInboundAt != null && (now ?? DateTime.now()).difference(lastInboundAt!) < window;

  Duration? remaining([DateTime? now]) {
    if (lastInboundAt == null) return null;
    final left = window - (now ?? DateTime.now()).difference(lastInboundAt!);
    return left.isNegative ? null : left;
  }

  factory OutreachConversation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      OutreachConversation(lastInboundAt: tsToDate(doc.data()?['lastInboundAt']));
}
