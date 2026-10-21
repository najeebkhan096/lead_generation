import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/sales_user.dart';

/// How many new leads a salesman has contacted today, against their limit.
class DailyContactStatus {
  const DailyContactStatus({required this.used, required this.limit});

  /// New leads contacted today.
  final int used;

  /// The most a salesman may contact in a day (set by an admin).
  final int limit;

  bool get reached => used >= limit;

  /// Contacts still allowed today.
  int get left => limit > used ? limit - used : 0;
}

/// The day a contact counts toward, as the server keys it: Asia/Qatar, which
/// is UTC+3 all year (no daylight saving). Keep in step with LEAD_DAY_TIMEZONE
/// in the functions.
String dailyDayKey(DateTime now) {
  final d = now.toUtc().add(const Duration(hours: 3));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Midnight at the start of [dayKey] in Asia/Qatar, as a UTC instant.
DateTime dailyDayStart(String dayKey) {
  final parts = dayKey.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]).subtract(const Duration(hours: 3));
}

/// Watches the signed-in salesman's daily limit and how many new leads they
/// have contacted today.
///
/// The count is the number of 1-star WhatsApp leads this salesman contacted
/// since the day began. That is what the server counts against the limit,
/// read from the leads themselves, so it needs no extra Firestore rule.
class DailyContactRepository {
  DailyContactRepository({FirebaseFirestore? firestore, DateTime Function()? clock})
      : _firestore = firestore,
        _clock = clock ?? DateTime.now;

  final FirebaseFirestore? _firestore;
  final DateTime Function() _clock;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Emits whenever the limit or today's count changes. A missing limit means
  /// the default. Errors are passed on, so the page can say so.
  Stream<DailyContactStatus> watchToday(String uid) {
    final user = _db.collection('users').doc(uid);
    final todayStart = Timestamp.fromDate(dailyDayStart(dailyDayKey(_clock())));
    final contactedToday = _db
        .collection('whatsappLeads')
        .where('sourceType', isEqualTo: 'review')
        .where('contactedBy', isEqualTo: uid)
        .where('contactedAt', isGreaterThanOrEqualTo: todayStart)
        // Newest first matches the deployed index; without it Firestore wants another one.
        .orderBy('contactedAt', descending: true);

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? limitSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? usedSub;
    int? limit;
    int? used;
    late final StreamController<DailyContactStatus> controller;

    void emit() {
      if (limit == null || used == null || controller.isClosed) return;
      controller.add(DailyContactStatus(used: used!, limit: limit!));
    }

    controller = StreamController<DailyContactStatus>(
      onListen: () {
        limitSub = user.snapshots().listen(
          (snap) {
            limit = (snap.data()?['dailyLeadLimit'] as num?)?.toInt() ?? SalesUser.defaultDailyLeadLimit;
            emit();
          },
          onError: controller.addError,
        );
        usedSub = contactedToday.snapshots().listen(
          (snap) {
            used = snap.size;
            emit();
          },
          onError: (Object e, StackTrace s) {
            debugPrint('[daily limit] could not count today\'s contacts: $e');
            controller.addError(e, s);
          },
        );
      },
      onCancel: () async {
        await limitSub?.cancel();
        await usedSub?.cancel();
      },
    );
    return controller.stream;
  }
}
