/// The app update rule for the Android app, as the backend stores it at
/// `appConfig/android`. The phone reads the same document to decide whether it
/// must update (see mobile/lib/services/app_update.dart).
class AppUpdateConfig {
  const AppUpdateConfig({
    this.minBuild = 0,
    this.latestBuild = 0,
    this.apkUrl = '',
    this.message = '',
    this.updatedAt,
  });

  /// The oldest build allowed to run. Anything below it must update.
  final int minBuild;

  /// The newest build available.
  final int latestBuild;

  /// Where the phone downloads the newest APK from. Empty until one is uploaded.
  final String apkUrl;

  /// Shown on the update page. Empty means the app's default message.
  final String message;
  final DateTime? updatedAt;

  factory AppUpdateConfig.fromJson(Map<String, dynamic> json) {
    return AppUpdateConfig(
      minBuild: (json['minBuild'] as num?)?.toInt() ?? 0,
      latestBuild: (json['latestBuild'] as num?)?.toInt() ?? 0,
      apkUrl: (json['apkUrl'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      updatedAt: json['updatedAt'] is String ? DateTime.tryParse(json['updatedAt'] as String)?.toLocal() : null,
    );
  }
}
