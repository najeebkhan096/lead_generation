import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/outreach_message.dart';

class OutreachApiException implements Exception {
  final String message;
  final String? code;
  final int? status;
  const OutreachApiException(this.message, {this.code, this.status});

  bool get windowClosed => code == 'WINDOW_CLOSED';

  @override
  String toString() => message;
}

/// Client for the `outreachApi` Cloud Function. The function holds the Twilio
/// credentials; this app only sends its Firebase Auth identity (added by the SDK).
class OutreachApi {
  OutreachApi({FirebaseFunctions? functions})
      : _fn = (functions ?? FirebaseFunctions.instanceFor(region: 'us-central1')).httpsCallable(
          'outreachApi',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
        );

  final HttpsCallable _fn;

  Future<Map<String, dynamic>> _post(String action, Map<String, dynamic> body) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw const OutreachApiException('You are signed out.', code: 'UNAUTHENTICATED');
    }
    try {
      final res = await _fn.call<dynamic>({'action': action, ...body});
      final data = res.data;
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final appCode = details is Map ? details['code'] as String? : null;
      debugPrint('[Outreach] $action failed: ${e.code} ${e.message}');
      switch (e.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          throw OutreachApiException(
              appCode == 'TWILIO_NOT_CONFIGURED'
                  ? (e.message ?? 'Twilio is not configured.')
                  : 'Cannot reach the server. Check your connection.',
              code: appCode ?? 'NETWORK');
        case 'not-found' when appCode == null:
          throw const OutreachApiException(
              'The chat function is not deployed yet (firebase deploy --only functions).',
              code: 'NOT_DEPLOYED');
        default:
          throw OutreachApiException(e.message ?? 'Request failed (${e.code})', code: appCode ?? e.code);
      }
    }
  }

  Future<void> sendText({required String leadId, required String messageId, required String body, String? replyTo}) =>
      _post('text',
          {'leadId': leadId, 'messageId': messageId, 'body': body, 'replyToMessageId': replyTo});

  Future<void> sendMedia({
    required String leadId,
    required String messageId,
    required MediaInfo media,
    String caption = '',
    String? replyTo,
  }) =>
      _post('media', {
        'leadId': leadId,
        'messageId': messageId,
        'media': media.toApiJson(),
        'caption': caption,
        'replyToMessageId': replyTo,
      });

  /// [mediaUrl] is the Firebase download URL of the uploaded header image; the
  /// backend strips the template's fixed prefix (error 21620 otherwise).
  Future<void> sendTemplate({required String leadId, required String messageId, required String mediaUrl}) =>
      _post('template', {'leadId': leadId, 'messageId': messageId, 'mediaUrl': mediaUrl});

  Future<void> retry({required String leadId, required String messageId}) =>
      _post('retry', {'leadId': leadId, 'messageId': messageId});

  /// [emoji] null removes the reaction. Stored in Firestore only (not sent to WhatsApp).
  Future<void> react({required String leadId, required String messageId, String? emoji}) =>
      _post('react', {'leadId': leadId, 'messageId': messageId, 'emoji': emoji});

  /// Optional fallback when a status callback never arrived.
  Future<void> refreshStatus({required String leadId, required String messageId}) =>
      _post('refresh', {'leadId': leadId, 'messageId': messageId});

  Future<String> ensureLead({
    required String name,
    required String businessName,
    required String phoneNumber,
    Map<String, String> details = const {},
  }) async {
    final r = await _post('ensureLead',
        {'name': name, 'businessName': businessName, 'phoneNumber': phoneNumber, 'details': details});
    return r['id'] as String;
  }

  Future<({int found, int created})> importFromTwilio() async {
    final r = await _post('importTwilio', {});
    return (found: (r['found'] as num).toInt(), created: (r['created'] as num).toInt());
  }

  Future<int> backfill(String leadId) async {
    final r = await _post('backfill', {'leadId': leadId});
    return (r['added'] as num?)?.toInt() ?? 0;
  }
}
