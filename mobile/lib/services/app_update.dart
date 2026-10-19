import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The update rule kept in Firestore at `appConfig/android`. Set by an admin
/// in the Firebase console; the app only reads it.
class AppUpdateRule {
  const AppUpdateRule({
    required this.minBuild,
    required this.latestBuild,
    required this.apkUrl,
    required this.message,
  });

  /// The oldest build allowed to run. Anything below it must update.
  final int minBuild;

  /// The newest build available, for the message only.
  final int latestBuild;

  /// Where to download the new APK.
  final String apkUrl;

  /// Shown on the update page.
  final String message;

  static const defaultMessage =
      'A new version of LeadFinder is required to continue. Download it, install it over this app, then open LeadFinder again.';

  factory AppUpdateRule.fromData(Map<String, dynamic> data) {
    return AppUpdateRule(
      minBuild: (data['minBuild'] as num?)?.toInt() ?? 0,
      latestBuild: (data['latestBuild'] as num?)?.toInt() ?? 0,
      apkUrl: (data['apkUrl'] as String?)?.trim() ?? '',
      message: (data['message'] as String?)?.trim().isNotEmpty == true ? (data['message'] as String).trim() : defaultMessage,
    );
  }
}

/// Whether an install with [installedBuild] must update to run.
bool updateRequired({required int installedBuild, required int minBuild}) => installedBuild < minBuild;

/// Checks the rule against this install. Returns the rule when this install
/// must update, and null otherwise.
///
/// It fails open: if the rule cannot be read (offline, slow, or not set up yet),
/// the app runs as usual, so a network problem never locks the team out.
class AppUpdateCheck {
  AppUpdateCheck({FirebaseFirestore? firestore, Future<int> Function()? installedBuild})
      : _firestore = firestore,
        _installedBuild = installedBuild ?? _buildFromPackage;

  final FirebaseFirestore? _firestore;
  final Future<int> Function() _installedBuild;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  static Future<int> _buildFromPackage() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<AppUpdateRule?> requiredUpdate() async {
    // Only the Android APK is distributed outside the store for now.
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final snap = await _db
          .collection('appConfig')
          .doc('android')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = snap.data();
      if (data == null) return null;
      final rule = AppUpdateRule.fromData(data);
      final build = await _installedBuild();
      return updateRequired(installedBuild: build, minBuild: rule.minBuild) ? rule : null;
    } catch (_) {
      return null;
    }
  }
}
