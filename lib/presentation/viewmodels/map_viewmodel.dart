import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wasfa_rider/data/repositories/order_repository.dart';

class MapViewModel extends ChangeNotifier {
  // ══════════════════════════════════════════════════════════════
  // TEMPORARY — TEST-ONLY LOCATION OVERRIDE
  // Turn this on to pin "your" position to a fixed test coordinate
  // instead of reading the real device GPS. Useful when testing from
  // outside Kuwait — no real GPS stream is started at all while this
  // is on, so it works with zero device/emulator setup.
  //
  //   >>> MUST BE SET BACK TO false BEFORE BUILDING THE APK <<<
  //   >>> FOR THE CLIENT OR ANY OUTSIDE TESTER.              <<<
  //
  // A "TEST LOCATION" badge appears on the Home map screen whenever
  // this is true, as a safeguard so it's obvious before you ship.
  static const bool kDebugFakeDriverLocation = false; // <-- SET false BEFORE RELEASE BUILD
  static const LatLng kDebugFakeLocationCoord = LatLng(29.3759, 47.9774); // change freely while testing
  // ══════════════════════════════════════════════════════════════

  LatLng? _driverPosition;
  StreamSubscription<Position>? _positionStream;
  bool _tracking = false;
  String? _error;

  LatLng? get driverPosition => _driverPosition;
  bool get tracking => _tracking;
  String? get error => _error;
  bool get isFakingLocation => kDebugFakeDriverLocation;

  /// Default Kuwait City centre for map initialization
  static const LatLng kuwaitCity = LatLng(29.3759, 47.9774);

  // ── Public API ────────────────────────────────────────────────
  Future<void> startTracking() async {
    // CLIENT-REPORTED (2026-08-13): video showed rapid repeated Home ↔
    // Orders ↔ Profile tab-switching leading to the app appearing stuck.
    // Root cause candidate: tabs aren't a persistent IndexedStack — main.dart
    // fully disposes and rebuilds each screen on every switch — so every
    // single Home mount called startTracking() again via
    // didChangeDependencies, even though the underlying GPS subscription
    // was already running fine from moments ago. That meant a fresh
    // _ensurePermission() native-channel round-trip (isLocationServiceEnabled
    // + checkPermission, at minimum) on every mount, which can queue up and
    // visibly stall the UI when triggered many times in quick succession on
    // a slower device. Skip all of that entirely when already tracking —
    // there's nothing to redo.
    if (_tracking && _positionStream != null) return;
    if (kDebugFakeDriverLocation) {
      // Test-only path — no permission check, no real GPS stream.
      await _positionStream?.cancel();
      _positionStream = null;
      _driverPosition = kDebugFakeLocationCoord;
      _tracking = true;
      _error = null;
      notifyListeners();
      return;
    }
    final ok = await _ensurePermission();
    if (!ok) return;
    await _positionStream?.cancel(); // guard against double-subscribe if called twice without stopTracking()
    _tracking = true;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (pos) {
        _driverPosition = LatLng(pos.latitude, pos.longitude);
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
    notifyListeners();
  }

  void stopTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _tracking = false;
    notifyListeners();
  }

  // ── Live-location sharing (customer app "Track Order") ─────────
  // REMOVED (2026-08-25): this called a GUESSED endpoint
  // (POST /orders/{co}/location) that was never confirmed with backend
  // — client confirmed live via Postman that it returns a genuine 404,
  // "The route api/driver/orders/{co}/location could not be found."
  // This had been actively firing every 12 seconds for every "on my
  // way" delivery, hitting a route that has never existed. If this
  // feature (customer app seeing the driver's live position) is still
  // wanted, ask backend for the real endpoint first, then wire it in —
  // per the explicit instruction not to ship guessed/dummy API calls.

  // ── Internal helpers ──────────────────────────────────────────
  // CLIENT-ASKED (2026-08-22): confirmed correct that re-requesting is
  // the right approach for a plain "denied" — but Android/iOS both have
  // a SECOND denial state ("denied forever" / permanently blocked at the
  // OS level) where calling requestPermission() again will NEVER show
  // the native popup again, by OS design — no amount of retrying from
  // the app can bring it back. The only fix at that point is directing
  // the driver to the phone's own Settings app. This picks the correct
  // action for whichever state actually occurred, rather than always
  // just retrying.
  Future<void> retryLocationPermission() async {
    if (_error == 'Location permissions permanently denied.') {
      await Geolocator.openAppSettings();
    } else {
      await startTracking(); // re-runs _ensurePermission(), showing the native popup again if that's actually still possible
    }
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _error = 'Location services are disabled.';
      notifyListeners();
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _error = 'Location permissions denied.';
        notifyListeners();
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _error = 'Location permissions permanently denied.';
      notifyListeners();
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
