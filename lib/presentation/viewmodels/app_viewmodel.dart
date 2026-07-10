import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/order_repository.dart';

/// Top-level app ViewModel — manages driver session, language, shift toggle.
/// Now backed by real API calls (see AuthRepository / OrderRepository).
class AppViewModel extends ChangeNotifier {
  final _authRepo = AuthRepository();
  final _orderRepo = OrderRepository();

  /// Kicked off once in the constructor; RiderShell awaits this exactly
  /// once (in initState) to decide whether to auto-jump into the app.
  /// Deliberately NOT re-checked on every build — that caused a race with
  /// logout() (stale isLoggedIn read while logout's own future was still
  /// in flight could bounce the phase back to 'app' with a null driver).
  late final Future<void> sessionRestoreFuture = restoreSession();

  String _language = 'en';
  bool _isLoggedIn = false;
  DriverProfile? _driver;

  bool isLoading = false;
  String? error;

  String get language => _language;
  bool get isLoggedIn => _isLoggedIn;
  DriverProfile? get driver => _driver;
  bool get isRTL => _language == 'ar';

  /// Call once at app start to restore a session if a token is stored.
  Future<void> restoreSession() async {
    if (await _authRepo.isLoggedIn) {
      try {
        _driver = await _authRepo.fetchMe();
        _isLoggedIn = true;
        if (_driver?.language != null) _language = _driver!.language!;
      } catch (_) {
        // Couldn't confirm the session (invalid/expired token, OR no
        // network — a DNS/connection failure throws the same ApiException
        // type). Either way, just clear the LOCAL token and fall back to
        // the login screen. Deliberately NOT calling the full logout()
        // here — that makes its own network call (POST /logout), which
        // would ALSO fail if we're offline, throwing a second unhandled
        // exception that used to hang the splash screen forever.
        await ApiClient.instance.clearToken();
        _isLoggedIn = false;
      }
      notifyListeners();
    }
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    notifyListeners();
    // /language requires a bearer token (401 otherwise) — only sync once
    // logged in. Pre-login language choice stays local-only, which matches
    // the current UI flow (language picker is the very first screen).
    if (!_isLoggedIn) return;
    try {
      await _orderRepo.setLanguage(lang);
    } on ApiException {
      // Non-critical — keep the local change even if the sync call fails.
    }
  }

  // ── OTP auth flow ────────────────────────────────────────────
  String? devOtpHint; // shown to help testing when backend returns dev_code

  Future<bool> requestOtp(String phone) async {
    isLoading = true;
    error = null;
    devOtpHint = null;
    notifyListeners();
    try {
      final res = await _authRepo.requestOtp(phone);
      if (!res.exists) {
        error = 'This number isn\'t registered as a driver yet. Ask an admin to add it in the admin panel first.';
        return false;
      }
      if (res.devCode != null) {
        devOtpHint = res.devCode; // dev/sandbox environments send the real OTP back directly
      }
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String phone, String code) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _authRepo.verifyOtp(phone, code);
      _driver = await _authRepo.fetchMe();
      _isLoggedIn = true;
      // The driver just picked a language on the screen before this login
      // (see LanguageScreen) — that pick couldn't sync to the server yet
      // since they weren't authenticated. Push it now rather than pulling
      // _driver.language down, which would silently override what they
      // just chose with a possibly-stale previous value.
      unawaited(setLanguage(_language));
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Vehicle setup happens right after OTP verification in the current UI.
  Future<bool> completeVehicleSetup({required String vehicleType, required String plateNumber}) async {
    try {
      await _orderRepo.setVehicle(vehicleType: vehicleType, plateNumber: plateNumber);
      if (_driver != null) {
        _driver!.vehicleType = _vehicleFrom(vehicleType);
        _driver!.plateNumber = plateNumber;
        _driver!.onShift = true;
        notifyListeners();
      }
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleShift() async {
    if (_driver == null) return;
    final newValue = !_driver!.onShift;
    try {
      await _orderRepo.setShift(newValue);
      _driver!.onShift = newValue;
      notifyListeners();
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authRepo.logout();
    _isLoggedIn = false;
    _driver = null;
    notifyListeners();
  }

  void addEarnings(double amount) {
    if (_driver != null) {
      _driver!.todayEarnings += amount;
      _driver!.deliveriesToday += 1;
      notifyListeners();
    }
  }

  VehicleType _vehicleFrom(String s) {
    switch (s) {
      case 'car': return VehicleType.car;
      case 'scooter': return VehicleType.scooter;
      default: return VehicleType.motorbike;
    }
  }
}
