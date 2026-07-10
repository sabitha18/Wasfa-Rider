import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/order_repository.dart';
import '../../viewmodels/map_viewmodel.dart';

/// Full-screen in-app map for a single order — shows the driver's live
/// location and the destination pin without leaving the app (replaces
/// launching the external Google Maps app).
///
/// Note: this only shows a straight line between the two points, not a
/// real driving route — turn-by-turn routing needs the Directions API
/// (a separate Google Cloud API + billing, and ideally a backend proxy
/// so the API key isn't shipped in the app). Ask backend if that's
/// planned; until then this is "where things are", not "how to get there".
class InAppMapScreen extends StatefulWidget {
  const InAppMapScreen({super.key, required this.order, required this.onBack});
  final Order order;
  final VoidCallback onBack;

  @override
  State<InAppMapScreen> createState() => _InAppMapScreenState();
}

class _InAppMapScreenState extends State<InAppMapScreen> {
  GoogleMapController? _controller;
  LatLng? _destination;
  bool _loadingDestination = true;
  String? _destError;
  final _orderRepo = OrderRepository();

  @override
  void initState() {
    super.initState();
    context.read<MapViewModel>().startTracking();
    _resolveDestination();
  }

  Future<void> _resolveDestination() async {
    // If the order already came with real lat/lng (not the 0.5/0.5
    // placeholder used for the old fake map), use it directly.
    final o = widget.order;
    final hasRealPin = !(o.pinPos.leftFraction == 0.5 && o.pinPos.topFraction == 0.5);
    if (hasRealPin) {
      setState(() {
        _destination = LatLng(o.pinPos.topFraction, o.pinPos.leftFraction); // topFraction=lat, leftFraction=lng
        _loadingDestination = false;
      });
      return;
    }
    // Otherwise fall back to the /geocode/{co} endpoint.
    try {
      final co = o.co ?? o.id;
      final result = await _orderRepo.geocodeOrder(co);
      if (!mounted) return;
      if (result == null) {
        setState(() { _destError = "This order's address hasn't been located yet."; _loadingDestination = false; });
      } else {
        setState(() {
          _destination = LatLng(result.lat, result.lng);
          _loadingDestination = false;
        });
        _fitBounds();
      }
    } on ApiException catch (e) {
      // A 500 here is a backend bug (seen live: a PHP crash in the geocode
      // controller), not "this address can't be geocoded" — show the real
      // message so it's obvious this needs reporting to backend, not a
      // silent generic failure.
      if (!mounted) return;
      setState(() { _destError = 'Map error from server: ${e.message}'; _loadingDestination = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _destError = "Couldn't locate this address on the map."; _loadingDestination = false; });
    }
  }

  void _fitBounds() {
    final mapVM = context.read<MapViewModel>();
    final driver = mapVM.driverPosition;
    if (_controller == null || _destination == null) return;
    if (driver == null) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(_destination!, 15));
      return;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(
        driver.latitude < _destination!.latitude ? driver.latitude : _destination!.latitude,
        driver.longitude < _destination!.longitude ? driver.longitude : _destination!.longitude,
      ),
      northeast: LatLng(
        driver.latitude > _destination!.latitude ? driver.latitude : _destination!.latitude,
        driver.longitude > _destination!.longitude ? driver.longitude : _destination!.longitude,
      ),
    );
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  @override
  Widget build(BuildContext context) {
    final mapVM = context.watch<MapViewModel>();
    final driver = mapVM.driverPosition;

    final markers = <Marker>{
      if (_destination != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: _destination!,
          icon: BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(title: widget.order.patient, snippet: widget.order.addr1),
        ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You'),
        ),
    };

    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _destination ?? driver ?? MapViewModel.kuwaitCity,
            zoom: 14,
          ),
          markers: markers,
          myLocationEnabled: false, // we draw our own "You" marker above
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) {
            _controller = c;
            if (_destination != null) _fitBounds();
          },
        ),
        // Back button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: const Icon(Icons.arrow_back, color: WTheme.navy),
              ),
            ),
          ),
        ),
        // Loading / error banner
        if (_loadingDestination || _destError != null)
          Positioned(
            left: 16, right: 16, top: 68,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
              child: Text(
                _loadingDestination ? 'Locating address…' : _destError!,
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: WTheme.navy),
              ),
            ),
          ),
        // Bottom "re-center" button
        Positioned(
          right: 16,
          bottom: 32,
          child: GestureDetector(
            onTap: _fitBounds,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: const Icon(Icons.center_focus_strong, color: WTheme.navy),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    context.read<MapViewModel>().stopTracking();
    super.dispose();
  }
}
