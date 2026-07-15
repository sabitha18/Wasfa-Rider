import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  static const bool kDebugFakeDriverLocation = true; // <-- SET false BEFORE RELEASE BUILD
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

  // ── Internal helpers ──────────────────────────────────────────
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
