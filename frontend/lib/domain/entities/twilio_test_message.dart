import 'package:equatable/equatable.dart';

/// One message in a Twilio test lead's conversation
/// (`outreachConversations/{id}/messages/{messageId}`).
class TwilioTestMessage extends Equatable {
  const TwilioTestMessage({
    required this.id,
    required this.isOutbound,
    required this.type,
    required this.channel,
    required this.body,
    required this.status,
    this.errorCode,
    this.errorMessage,
    this.createdAt,
    this.mediaName,
  });

  final String id;
  final bool isOutbound;

  /// `text`, `template`, `image`, ...
  final String type;

  /// `whatsapp` or `sms`.
  final String channel;
  final String body;

  /// `sending`, `sent`, `delivered`, `read`, `failed`, `undelivered`.
  final String status;
  final int? errorCode;
  final String? errorMessage;
  final DateTime? createdAt;
  final String? mediaName;

  bool get isSms => channel == 'sms';
  bool get isTemplate => type == 'template';
  bool get hasFailed => status == 'failed' || status == 'undelivered';

  factory TwilioTestMessage.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    return TwilioTestMessage(
      id: json['id'] as String,
      isOutbound: json['direction'] != 'inbound',
      type: (json['type'] as String?) ?? 'text',
      channel: (json['channel'] as String?) ?? 'whatsapp',
      body: (json['body'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'sending',
      errorCode: (json['errorCode'] as num?)?.toInt(),
      errorMessage: json['errorMessage'] as String?,
      createdAt: created is num ? DateTime.fromMillisecondsSinceEpoch(created.toInt()) : null,
      mediaName: json['mediaName'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [id, isOutbound, type, channel, body, status, errorCode, errorMessage, createdAt, mediaName];
}

/// A conversation, oldest message first.
class TwilioTestChat extends Equatable {
  const TwilioTestChat({required this.messages, this.windowClosesAt});

  final List<TwilioTestMessage> messages;

  /// When WhatsApp free-text stops being allowed (24h after the lead's last
  /// WhatsApp reply). Null = closed: only the template or SMS can be sent.
  final DateTime? windowClosesAt;

  bool get windowOpen => windowClosesAt != null && windowClosesAt!.isAfter(DateTime.now());

  factory TwilioTestChat.fromJson(Map<String, dynamic> json) {
    final closes = json['windowClosesAt'];
    return TwilioTestChat(
      messages: ((json['messages'] as List<dynamic>?) ?? const [])
          .map((e) => TwilioTestMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      windowClosesAt: closes is num ? DateTime.fromMillisecondsSinceEpoch(closes.toInt()) : null,
    );
  }

  @override
  List<Object?> get props => [messages, windowClosesAt];
}
