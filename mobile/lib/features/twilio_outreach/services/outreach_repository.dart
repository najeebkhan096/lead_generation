import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/outreach_lead.dart';
import '../models/outreach_message.dart';
import 'outreach_api.dart';

class MessagePage {
  const MessagePage(this.messages, this.rawCount);
  final List<OutreachMessage> messages;
  final int rawCount;
}

/// Firestore access for the outreach inbox. Realtime streams only — the
/// backend (Twilio webhooks) is what writes new messages and statuses.
class OutreachRepository {
  OutreachRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) throw StateError('Not signed in');
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _leads => _db.collection('outreachLeads');
  DocumentReference<Map<String, dynamic>> _conv(String id) => _db.collection('outreachConversations').doc(id);
  CollectionReference<Map<String, dynamic>> _messages(String id) => _conv(id).collection('messages');

  /// Newest activity first. Sorted client-side so no composite index is needed.
  Stream<List<OutreachLead>> watchLeads() {
    return _leads.where('ownerId', isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs.map(OutreachLead.fromDoc).toList()
        ..sort((a, b) => b.activityAt.compareTo(a.activityAt));
      return list;
    });
  }

  Stream<OutreachLead?> watchLead(String id) =>
      _leads.doc(id).snapshots().map((d) => d.exists ? OutreachLead.fromDoc(d) : null);

  Stream<OutreachConversation> watchConversation(String id) =>
      _conv(id).snapshots().map(OutreachConversation.fromDoc);

  /// Newest first (matches a reversed ListView). Hidden ("deleted") messages are
  /// dropped, but [MessagePage.rawCount] still counts them (pagination).
  Stream<MessagePage> watchMessages(String conversationId, {int limit = 50}) {
    return _messages(conversationId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => MessagePage(
              s.docs.map(OutreachMessage.fromDoc).where((m) => m.deletedAt == null).toList(),
              s.docs.length,
            ));
  }

  String newMessageId(String conversationId) => _messages(conversationId).doc().id;

  Future<void> markRead(String leadId) => _leads.doc(leadId).update({'unreadCount': 0});

  Future<void> renameLead(String leadId, {required String name, required String businessName}) =>
      _leads.doc(leadId).update({'name': name, 'businessName': businessName, 'unreadCount': 0});

  /// Hides a message for this user only: WhatsApp has no "unsend" via Twilio.
  Future<void> hideMessage(String conversationId, String messageId) =>
      _messages(conversationId).doc(messageId).update({'deletedAt': FieldValue.serverTimestamp()});

  // ---- one-time migration of the old device-local lead list ------------------

  static const _legacyKey = 'saved_clients';
  static String _migratedKey(String uid) => 'outreach_leads_migrated_$uid';

  /// Copies leads saved by the previous SharedPreferences-based version into
  /// Firestore (through the backend, so conversation docs exist too). The local
  /// list is left untouched as a backup; runs once per account, retries on failure.
  Future<int> migrateLegacyLeads(OutreachApi api) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey(uid)) == true) return 0;
    // The old screen saved a List<String>, one JSON object per lead.
    final raw = prefs.getStringList(_legacyKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setBool(_migratedKey(uid), true);
      return 0;
    }
    var moved = 0;
    try {
      for (final item in raw) {
        final Map<String, dynamic> m;
        try {
          m = Map<String, dynamic>.from(jsonDecode(item) as Map);
        } catch (_) {
          continue; // corrupt entry: skip, keep the rest
        }
        try {
          await api.ensureLead(
            name: (m['name'] ?? '').toString(),
            businessName: (m['businessName'] ?? '').toString(),
            phoneNumber: (m['phoneNumber'] ?? '').toString(),
          );
          moved++;
        } on OutreachApiException catch (e) {
          if (e.code == 'INVALID_PHONE') continue; // skip junk, keep going
          rethrow;
        }
      }
      await prefs.setBool(_migratedKey(uid), true);
    } catch (e) {
      debugPrint('[Outreach] legacy lead migration deferred: $e');
    }
    return moved;
  }
}
