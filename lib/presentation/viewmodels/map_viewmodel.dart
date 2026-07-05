import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapViewModel extends ChangeNotifier {
  LatLng? _driverPosition;
  StreamSubscription<Position>? _positionStream;
  bool _tracking = false;
  String? _error;

  LatLng? get driverPosition => _driverPosition;
  bool get tracking => _tracking;
  String? get error => _error;

  /// Default Kuwait City centre for map initialization
  static const LatLng kuwaitCity = LatLng(29.3759, 47.9774);

  // ── Public API ────────────────────────────────────────────────
  Future<void> startTracking() async {
    final ok = await _ensurePermission();
    if (!ok) return;
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
