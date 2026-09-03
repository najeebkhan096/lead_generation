import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum WhatsAppClaimOutcome { claimed, alreadyMine, taken, failed }

/// First salesman to tap WhatsApp on a verified business owns it.
/// Others no longer see that row. Phone number is the identity so the
/// same business in two upload batches is still claimed once.
class WhatsAppClaimStore {
  WhatsAppClaimStore({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const collection = 'whatsappClaims';

  final FirebaseFirestore _db;

  static String claimIdFromRow(Map<String, dynamic> row) {
    final digits = (row['Phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) return digits;
    final name = (row['Business Name'] ?? '').toString().trim().toLowerCase();
    final slug = name.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final clipped = slug.length > 80 ? slug.substring(0, 80) : slug;
    return 'n_${clipped.isEmpty ? 'unknown' : clipped}';
  }

  /// Live map of claimId → salesman uid. Small docs, so a full-collection
  /// listen is how every phone drops a lead the moment someone else taps it
  /// — even if that phone is still serving the 24-hour businesses cache.
  Stream<Map<String, String>> watchClaimedBy() {
    return _db.collection(collection).snapshots().map((snap) {
      final out = <String, String>{};
      for (final doc in snap.docs) {
        final by = doc.data()['claimedBy'] as String?;
        if (by != null && by.isNotEmpty) out[doc.id] = by;
      }
      return out;
    });
  }

  static bool visibleTo(String claimId, Map<String, String> claimedBy, String? uid) {
    final owner = claimedBy[claimId];
    if (owner == null) return true;
    return owner == uid;
  }

  static bool isMine(String claimId, Map<String, String> claimedBy, String? uid) {
    return uid != null && claimedBy[claimId] == uid;
  }

  Future<WhatsAppClaimOutcome> claimRow(Map<String, dynamic> row) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return WhatsAppClaimOutcome.failed;
    final id = claimIdFromRow(row);
    final ref = _db.collection(collection).doc(id);
    try {
      return await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) {
          final owner = snap.data()?['claimedBy'];
          if (owner == user.uid) return WhatsAppClaimOutcome.alreadyMine;
          return WhatsAppClaimOutcome.taken;
        }
        tx.set(ref, {
          'claimedBy': user.uid,
          'claimedByName': user.displayName ?? user.email,
          'phone': (row['Phone'] ?? '').toString(),
          'businessName': (row['Business Name'] ?? '').toString(),
          'claimedAt': FieldValue.serverTimestamp(),
        });
        return WhatsAppClaimOutcome.claimed;
      });
    } catch (_) {
      return WhatsAppClaimOutcome.failed;
    }
  }
}

mixin WhatsAppClaimsMixin<T extends StatefulWidget> on State<T> {
  final WhatsAppClaimStore claimStore = WhatsAppClaimStore();
  Map<String, String> claimedBy = {};
  StreamSubscription<Map<String, String>>? _claimsSub;

  @override
  void initState() {
    super.initState();
    _claimsSub = claimStore.watchClaimedBy().listen((map) {
      if (mounted) setState(() => claimedBy = map);
    });
  }

  @override
  void dispose() {
    _claimsSub?.cancel();
    super.dispose();
  }

  String? get _claimUid => FirebaseAuth.instance.currentUser?.uid;

  bool claimVisible(Map<String, dynamic> row) {
    return WhatsAppClaimStore.visibleTo(
      WhatsAppClaimStore.claimIdFromRow(row),
      claimedBy,
      _claimUid,
    );
  }

  bool claimIsMine(Map<String, dynamic> row) {
    return WhatsAppClaimStore.isMine(
      WhatsAppClaimStore.claimIdFromRow(row),
      claimedBy,
      _claimUid,
    );
  }

  Future<bool> claimAndOpen(Map<String, dynamic> row) async {
    final outcome = await claimStore.claimRow(row);
    if (!mounted) return false;
    final id = WhatsAppClaimStore.claimIdFromRow(row);
    final uid = _claimUid;
    switch (outcome) {
      case WhatsAppClaimOutcome.claimed:
      case WhatsAppClaimOutcome.alreadyMine:
        if (uid != null) {
          setState(() => claimedBy = {...claimedBy, id: uid});
        }
        return true;
      case WhatsAppClaimOutcome.taken:
        setState(() {
          if (claimedBy[id] == null) claimedBy = {...claimedBy, id: '_taken'};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This lead is no longer available.')),
        );
        return false;
      case WhatsAppClaimOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred. Please try again.')),
        );
        return false;
    }
  }
}
