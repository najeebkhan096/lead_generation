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
/// ONE limit covers both kinds of lead, so the count is the 1-star WhatsApp
/// leads plus the no-website leads this salesman contacted since the day began.
/// That is what the server counts against the limit, read from the leads
/// themselves, so it needs no extra Firestore rule.
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
    // Newest first matches the deployed indexes; without it Firestore wants others.
    final reviewToday = _db
        .collection('whatsappLeads')
        .where('sourceType', isEqualTo: 'review')
        .where('contactedBy', isEqualTo: uid)
        .where('contactedAt', isGreaterThanOrEqualTo: todayStart)
        .orderBy('contactedAt', descending: true);
    final websiteToday = _db
        .collection('websiteLeads')
        .where('contactedBy', isEqualTo: uid)
        .where('contactedAt', isGreaterThanOrEqualTo: todayStart)
        .orderBy('contactedAt', descending: true);

    final subs = <StreamSubscription<dynamic>>[];
    int? limit;
    int? reviewUsed;
    int? websiteUsed;
    late final StreamController<DailyContactStatus> controller;

    // Nothing is shown until the limit and both counts are known, so the
    // banner never flashes a count that is only half of today's.
    void emit() {
      if (limit == null || reviewUsed == null || websiteUsed == null || controller.isClosed) return;
      controller.add(DailyContactStatus(used: reviewUsed! + websiteUsed!, limit: limit!));
    }

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>> count(
      Query<Map<String, dynamic>> query,
      String what,
      void Function(int n) set,
    ) =>
        query.snapshots().listen(
          (snap) {
            set(snap.size);
            emit();
          },
          onError: (Object e, StackTrace s) {
            debugPrint('[daily limit] could not count today\'s $what contacts: $e');
            controller.addError(e, s);
          },
        );

    controller = StreamController<DailyContactStatus>(
      onListen: () {
        subs.add(user.snapshots().listen(
          (snap) {
            limit = (snap.data()?['dailyLeadLimit'] as num?)?.toInt() ?? SalesUser.defaultDailyLeadLimit;
            emit();
          },
          onError: controller.addError,
        ));
        subs.add(count(reviewToday, '1-star', (n) => reviewUsed = n));
        subs.add(count(websiteToday, 'no-website', (n) => websiteUsed = n));
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }
}
