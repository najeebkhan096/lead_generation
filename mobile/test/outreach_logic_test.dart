import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lead_mobile/features/twilio_outreach/models/outreach_lead.dart';
import 'package:lead_mobile/features/twilio_outreach/models/outreach_message.dart';
import 'package:lead_mobile/features/twilio_outreach/services/media_service.dart';
import 'package:lead_mobile/features/twilio_outreach/widgets/message_bubble.dart';

void main() {
  group('24h window', () {
    final now = DateTime(2026, 1, 10, 12);
    test('open within 24h of last inbound', () {
      expect(OutreachConversation(lastInboundAt: now.subtract(const Duration(hours: 23))).isWindowOpen(now), isTrue);
    });
    test('closed after 24h or when they never wrote', () {
      expect(OutreachConversation(lastInboundAt: now.subtract(const Duration(hours: 25))).isWindowOpen(now), isFalse);
      expect(const OutreachConversation().isWindowOpen(now), isFalse);
      expect(const OutreachConversation().remaining(now), isNull);
    });
  });

  group('MediaService', () {
    test('sanitizes names but keeps the extension', () {
      expect(MediaService.sanitizeName('My Résumé (final).PDF'), 'My_R_sum_final_.pdf');
    });
    test('humanSize', () {
      expect(MediaService.humanSize(512), '512 B');
      expect(MediaService.humanSize(2048), '2 KB');
      expect(MediaService.humanSize(3 * 1024 * 1024), '3.0 MB');
    });
    test('rejects unsupported extensions before touching the file', () async {
      expect(() => MediaService.validate('/nonexistent/archive.zip'), throwsA(isA<MediaValidationException>()));
      expect(() => MediaService.validate('/nonexistent/run.exe'), throwsA(isA<MediaValidationException>()));
    });
  });

  group('message presentation', () {
    test('preview text for media-only messages', () {
      OutreachMessage m(MessageType t, {String? name}) => OutreachMessage(
            id: 'a',
            conversationId: 'c',
            direction: MessageDirection.inbound,
            type: t,
            createdAt: DateTime(2026),
            media: name == null ? null : MediaInfo(mimeType: 'x', fileName: name),
          );
      expect(m(MessageType.image).preview, '📷 Photo');
      expect(m(MessageType.video).preview, '🎥 Video');
      expect(m(MessageType.audio).preview, '🎤 Audio');
      expect(m(MessageType.document, name: 'a.pdf').preview, '📄 a.pdf');
    });
    test('failed state covers server and local failures', () {
      OutreachMessage m(MessageStatus s, {String? local}) => OutreachMessage(
          id: 'a', conversationId: 'c', direction: MessageDirection.outbound, type: MessageType.text,
          createdAt: DateTime(2026), status: s, localError: local);
      expect(m(MessageStatus.failed).hasFailed, isTrue);
      expect(m(MessageStatus.undelivered).hasFailed, isTrue);
      expect(m(MessageStatus.sending, local: 'x').hasFailed, isTrue);
      expect(m(MessageStatus.read).hasFailed, isFalse);
    });
    test('day labels', () {
      final now = DateTime(2026, 3, 10, 9);
      expect(dayLabel(DateTime(2026, 3, 10, 1), now), 'Today');
      expect(dayLabel(DateTime(2026, 3, 9, 23), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 1, 2), now), '2 Jan');
    });
  });

  group('voice notes + reactions', () {
    test('voice media round-trips and plays the AAC original', () {
      final m = MediaInfo.fromMap({
        'storagePath': 'outreach_media/u/c/m/voice.ogg',
        'playbackPath': 'outreach_media/u/c/m/voice_1.m4a',
        'mimeType': 'audio/ogg',
        'fileName': 'voice.ogg',
        'voice': true,
      });
      expect(m.voice, isTrue);
      expect(m.playablePath, 'outreach_media/u/c/m/voice_1.m4a');
      expect(m.toApiJson()['voice'], isTrue);
      expect(const MediaInfo(mimeType: 'audio/ogg', fileName: 'a.ogg', storagePath: 'p').playablePath, 'p');
      expect(const MediaInfo(mimeType: 'audio/ogg', fileName: 'a.ogg').toApiJson().containsKey('voice'), isFalse);
    });

    test('recorded voice note is wrapped as audio/mp4 and flagged', () async {
      final f = File('${Directory.systemTemp.path}/vn_test.m4a')..writeAsBytesSync([1, 2, 3]);
      final v = await MediaService.voiceNote(f.path, 4200);
      expect(v.voice, isTrue);
      expect(v.mimeType, 'audio/mp4');
      expect(v.durationMs, 4200);
      expect(v.withDuration(1).voice, isTrue);
      f.writeAsBytesSync([]);
      expect(() => MediaService.voiceNote(f.path, 1), throwsA(isA<MediaValidationException>()));
      f.deleteSync();
      // users still cannot attach arbitrary m4a files
      expect(() => MediaService.validate('/x/song.m4a'), throwsA(isA<MediaValidationException>()));
    });

    test('reactionEmojis de-duplicates', () {
      final m = OutreachMessage(
        id: 'a',
        conversationId: 'c',
        direction: MessageDirection.inbound,
        type: MessageType.text,
        createdAt: DateTime(2026),
        reactions: const {'u1': '👍', 'u2': '👍', 'u3': '❤️'},
      );
      expect(m.reactionEmojis, ['👍', '❤️']);
    });
  });
}
