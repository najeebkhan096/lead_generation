import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

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

/// The day a contact counts toward, as the server keys it: Asia/Dubai, which
/// is UTC+4 all year. Keep in step with LEAD_DAY_TIMEZONE in the functions.
String dailyDayKey(DateTime now) {
  final d = now.toUtc().add(const Duration(hours: 4));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Watches the signed-in salesman's daily limit and today's contact count.
/// The server keeps both (see functions/src/leadContact.js), so this only reads.
class DailyContactRepository {
  DailyContactRepository({FirebaseFirestore? firestore, DateTime Function()? clock})
      : _firestore = firestore,
        _clock = clock ?? DateTime.now;

  final FirebaseFirestore? _firestore;
  final DateTime Function() _clock;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Emits whenever the limit or today's count changes. A missing limit means
  /// the default; a missing count means nothing contacted yet today.
  Stream<DailyContactStatus> watchToday(String uid) {
    final user = _db.collection('users').doc(uid);
    final today = user.collection('contactDays').doc(dailyDayKey(_clock()));

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? limitSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? usedSub;
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
        usedSub = today.snapshots().listen(
          (snap) {
            used = (snap.data()?['count'] as num?)?.toInt() ?? 0;
            emit();
          },
          onError: controller.addError,
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
