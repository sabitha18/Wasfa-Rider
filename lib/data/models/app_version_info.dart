/// One platform's block from `GET /api/driver/app/version`:
/// `{ min_version, latest_version, store_url, message, message_ar }`.
/// Same shape as the Customer app's `/api/v1/app/version` — edited in the
/// admin panel (App version → Rider), separately for Android / iOS.
class AppVersionInfo {
  /// Below this → force update (app blocked until updated).
  final String minVersion;

  /// Below this (but not below [minVersion]) → optional "new version" prompt.
  final String latestVersion;

  /// Store page the Update button opens.
  final String storeUrl;

  /// Optional custom text for the update screen/prompt (empty = default text).
  final String message;
  final String messageAr;

  const AppVersionInfo({
    required this.minVersion,
    required this.latestVersion,
    required this.storeUrl,
    required this.message,
    required this.messageAr,
  });

  static String _s(Map<String, dynamic> json, String key) => (json[key]?.toString() ?? '').trim();

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) => AppVersionInfo(
        minVersion: _s(json, 'min_version'),
        latestVersion: _s(json, 'latest_version'),
        storeUrl: _s(json, 'store_url'),
        message: _s(json, 'message'),
        messageAr: _s(json, 'message_ar'),
      );

  String messageFor(bool isArabic) => isArabic ? messageAr : message;
}
