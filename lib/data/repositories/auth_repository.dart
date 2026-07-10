import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../models/models.dart';

class OtpRequestResult {
  final bool exists;
  final String? devCode;
  OtpRequestResult({required this.exists, this.devCode});
}

/// Driver auth is phone + OTP only (confirmed) — NOT email/password.
/// The email/password `/login` route in the Postman collection appears to
/// be leftover from a different login path (staff/admin?) and is not used
/// here. If that turns out to be wrong, this is the only file to change.
class AuthRepository {
  final _api = ApiClient.instance;

  /// Step 1 — request an OTP be sent to [phone].
  /// CONFIRMED response shape (seen live): {"ok": true, "exists": bool, "dev_code": string|null}
  /// - exists=false means this phone isn't registered as a driver yet.
  /// - dev_code, when non-null, is the actual OTP in dev/sandbox environments
  ///   (bypasses real SMS) — handy for testing without a real text message.
  Future<OtpRequestResult> requestOtp(String phone) async {
    final res = await _api.post(ApiConfig.otpRequest, data: {'phone': _normalizePhone(phone)});
    return OtpRequestResult(
      exists: res['exists'] == true,
      devCode: res['dev_code'] as String?,
    );
  }

  /// Step 2 — verify the OTP. CONFIRMED v3 request body:
  /// {"phone": "...", "code": "...", "device_name": "..."} — `fcm_token`
  /// is no longer shown in this call's example (there's a separate
  /// /fcm-token endpoint for that); sending both is harmless if backend
  /// ignores the extra field.
  /// Response confirmed to include "token" (collection's test script reads
  /// `response.token`). Everything else about the response (driver profile
  /// fields) is a guess — call `fetchMe()` right after to get the real
  /// profile shape instead of trusting fields on this response.
  Future<String> verifyOtp(String phone, String code, {String? fcmToken, String? deviceName}) async {
    final res = await _api.post(ApiConfig.otpVerify, data: {
      'phone': _normalizePhone(phone),
      'code': code,
      'device_name': deviceName ?? 'flutter-app',
      if (fcmToken != null) 'fcm_token': fcmToken,
    });
    final token = res['token'] as String?;
    if (token == null) {
      throw ApiException('OTP verified but no token was returned by the server.');
    }
    await _api.saveToken(token);
    return token;
  }

  /// GET /me — CONFIRMED shape: {"driver": {id, name, phone, vehicle_type,
  /// plate_number, language, needs_vehicle, is_online, shift_started_at}}
  Future<DriverProfile> fetchMe() async {
    final res = await _api.get(ApiConfig.me);
    final driverJson = res['driver'] as Map<String, dynamic>? ?? res;
    return DriverProfile.fromApiMe(driverJson);
  }

  Future<void> registerFcmToken(String fcmToken) async {
    await _api.post(ApiConfig.fcmToken, data: {'fcm_token': fcmToken});
  }

  Future<void> logout() async {
    try {
      await _api.post(ApiConfig.logout);
    } finally {
      await _api.clearToken();
    }
  }

  Future<bool> get isLoggedIn => _api.hasToken;

  String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), ''); // Postman example: "96590000000" (no + or spaces)
}
