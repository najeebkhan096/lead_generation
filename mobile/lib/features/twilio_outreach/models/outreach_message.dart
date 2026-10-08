import 'package:cloud_firestore/cloud_firestore.dart';
import 'outreach_lead.dart';

enum MessageDirection { inbound, outbound }

enum MessageType { text, image, video, audio, document, template }

enum MessageStatus { sending, sent, delivered, read, failed, undelivered }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

class MediaInfo {
  final String? storagePath; // null while an inbound file is still being copied
  final String mimeType;
  final String fileName;
  final int? size;
  final int? durationMs;
  final String? error;

  /// Voice notes are sent as OGG/Opus (`storagePath`) but also keep the recorded
  /// AAC original here, because iOS cannot play OGG.
  final String? playbackPath;
  final bool voice;

  /// Local-only (optimistic outgoing bubble before/while uploading).
  final String? localPath;

  const MediaInfo({
    this.storagePath,
    required this.mimeType,
    required this.fileName,
    this.size,
    this.durationMs,
    this.error,
    this.playbackPath,
    this.voice = false,
    this.localPath,
  });

  Map<String, dynamic> toApiJson() => {
        'storagePath': storagePath,
        'mimeType': mimeType,
        'fileName': fileName,
        'size': size,
        if (durationMs != null) 'durationMs': durationMs,
        if (voice) 'voice': true,
      };

  /// What the in-app player should open.
  String? get playablePath => playbackPath ?? storagePath;

  factory MediaInfo.fromMap(Map<String, dynamic> m) => MediaInfo(
        storagePath: m['storagePath'] as String?,
        mimeType: (m['mimeType'] ?? '').toString(),
        fileName: (m['fileName'] ?? '').toString(),
        size: (m['size'] as num?)?.toInt(),
        durationMs: (m['durationMs'] as num?)?.toInt(),
        error: m['error'] as String?,
        playbackPath: m['playbackPath'] as String?,
        voice: m['voice'] == true,
      );
}

class OutreachMessage {
  final String id;
  final String conversationId;
  final MessageDirection direction;
  final MessageType type;
  final String body;
  final MediaInfo? media;
  final String? twilioSid;
  final MessageStatus status;
  final String senderId;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? failedAt;
  final int? errorCode;
  final String? errorMessage;
  final String? replyToMessageId;
  final DateTime? deletedAt;

  /// Emoji reactions by user id (`reactions.<uid>`). Inbox-only: WhatsApp via
  /// Twilio cannot carry a reaction to the contact.
  final Map<String, String> reactions;

  /// Local-only state for messages not yet visible in Firestore.
  final double? uploadProgress; // 0..1 while uploading
  final String? localError; // upload/request failed before reaching the server
  final bool isLocalOnly;

  const OutreachMessage({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.type,
    this.body = '',
    this.media,
    this.twilioSid,
    this.status = MessageStatus.sending,
    this.senderId = '',
    required this.createdAt,
    this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.failedAt,
    this.errorCode,
    this.errorMessage,
    this.replyToMessageId,
    this.deletedAt,
    this.reactions = const {},
    this.uploadProgress,
    this.localError,
    this.isLocalOnly = false,
  });

  bool get isOutbound => direction == MessageDirection.outbound;
  bool get hasFailed =>
      localError != null || status == MessageStatus.failed || status == MessageStatus.undelivered;
  bool get isUploading => uploadProgress != null;

  /// Plain-text summary (reply quotes, list previews, forward).
  String get preview {
    if (body.isNotEmpty) return body;
    switch (type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.audio:
        return '🎤 Audio';
      case MessageType.document:
        return '📄 ${media?.fileName ?? 'Document'}';
      case MessageType.template:
        return '📋 Outreach template';
      case MessageType.text:
        return '';
    }
  }

  static Map<String, String> _reactionsOf(Object? raw) => raw is Map
      ? {for (final e in raw.entries) if (e.value is String && (e.value as String).isNotEmpty) '${e.key}': e.value as String}
      : const {};

  /// Distinct emojis, most recent order not tracked (UI shows them in one chip).
  List<String> get reactionEmojis => reactions.values.toSet().toList();

  factory OutreachMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final media = d['media'];
    return OutreachMessage(
      id: doc.id,
      conversationId: (d['conversationId'] ?? '').toString(),
      direction: _enumByName(MessageDirection.values, d['direction'], MessageDirection.inbound),
      type: _enumByName(MessageType.values, d['type'], MessageType.text),
      body: (d['body'] ?? '').toString(),
      media: media is Map ? MediaInfo.fromMap(Map<String, dynamic>.from(media)) : null,
      twilioSid: d['twilioSid'] as String?,
      status: _enumByName(MessageStatus.values, d['status'], MessageStatus.sending),
      senderId: (d['senderId'] ?? '').toString(),
      createdAt: tsToDate(d['createdAt']) ?? DateTime.now(),
      sentAt: tsToDate(d['sentAt']),
      deliveredAt: tsToDate(d['deliveredAt']),
      readAt: tsToDate(d['readAt']),
      failedAt: tsToDate(d['failedAt']),
      errorCode: (d['errorCode'] as num?)?.toInt(),
      errorMessage: d['errorMessage'] as String?,
      replyToMessageId: d['replyToMessageId'] as String?,
      deletedAt: tsToDate(d['deletedAt']),
      reactions: _reactionsOf(d['reactions']),
    );
  }

  OutreachMessage copyWith({
    double? Function()? uploadProgress,
    String? Function()? localError,
    MessageStatus? status,
  }) =>
      OutreachMessage(
        id: id,
        conversationId: conversationId,
        direction: direction,
        type: type,
        body: body,
        media: media,
        twilioSid: twilioSid,
        status: status ?? this.status,
        senderId: senderId,
        createdAt: createdAt,
        sentAt: sentAt,
        deliveredAt: deliveredAt,
        readAt: readAt,
        failedAt: failedAt,
        errorCode: errorCode,
        errorMessage: errorMessage,
        replyToMessageId: replyToMessageId,
        deletedAt: deletedAt,
        reactions: reactions,
        uploadProgress: uploadProgress != null ? uploadProgress() : this.uploadProgress,
        localError: localError != null ? localError() : this.localError,
        isLocalOnly: isLocalOnly,
      );
}
