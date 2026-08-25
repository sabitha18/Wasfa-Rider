import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/order_repository.dart';
import '../../viewmodels/map_viewmodel.dart';
import '../../widgets/shared_widgets.dart';

/// Full-screen in-app map for a single order — shows the driver's live
/// location and the destination pin without leaving the app (replaces
/// launching the external Google Maps app).
///
/// Note: this only shows a straight line between the two points, not a
/// real driving route — turn-by-turn routing needs the Directions API
/// (a separate Google Cloud API + billing, and ideally a backend proxy
/// so the API key isn't shipped in the app). Ask backend if that's
/// planned; until then this is "where things are", not "how to get there".
///
/// CONFIRMED LIVE (2026-08-11): some orders (phone/POS-placed, no
/// structured address) come back with lat/lng null but a real
/// `map_link` (a Google Maps short link, e.g. maps.app.goo.gl/...)
/// instead. The short link itself has no coordinates in its URL — they
/// only appear after Google's server resolves the redirect — so this
/// follows that redirect once (a plain, unauthenticated request, NOT
/// through ApiClient — this goes to Google's servers, not WASFA's
/// backend, and must never carry the driver's Bearer token) and reads
/// the resulting `@lat,lng,zoom` segment off the final URL to place a
/// real pin. If that fails for any reason (network, unexpected URL
/// shape, timeout), falls back to just the "Open in Google Maps" button
/// with no in-app pin — never a dead end either way.
/// Priority when resolving the customer's own destination: real lat/lng
/// (pin) > map_link (resolved to a pin when possible, button always
/// shown) > /geocode/{co} (pin, last resort). The pharmacy's own pin
/// (when it has coordinates) is resolved independently and shown
/// alongside the customer's — see _resolveDestination — rather than one
/// replacing the other; camera framing still prioritizes whichever is
/// operationally relevant to the current delivery step.
enum _DestinationKind { pharmacy, customer }

class InAppMapScreen extends StatefulWidget {
  const InAppMapScreen({super.key, required this.order, required this.onBack, this.focusPharmacySellerId});
  final Order order;
  final VoidCallback onBack;
  // CLIENT-REPORTED (2026-08-19): every pharmacy's own "MAP" button on
  // Order Detail opened this same screen with the SAME generic order,
  // which always shows order.primaryPharmacy (always index 0 — the
  // FIRST pharmacy) as the destination, regardless of which pharmacy's
  // card was actually tapped. So tapping "3lcost"'s map button showed
  // Pharmaline Pharmacy's location instead — a different pharmacy
  // entirely. When set, this pins the destination to the specific
  // pharmacy that was actually tapped.
  final int? focusPharmacySellerId;

  @override
  State<InAppMapScreen> createState() => _InAppMapScreenState();
}

class _InAppMapScreenState extends State<InAppMapScreen> {
  GoogleMapController? _controller;
  // CLIENT-REPORTED (2026-08-13): "we need both pharmacy and customer
  // shown" — the previous version resolved a single _destination that
  // switched to whichever was relevant for the current step, meaning
  // only ONE of the two ever appeared at a time. Split into two fields
  // so both can be visible together regardless of step.
  //
  // CLIENT-REPORTED (2026-08-22): _pharmacyDestination used to be a
  // plain cached field, set once when the screen first resolved its
  // destination. For a multi-pharmacy order, tapping a DIFFERENT
  // pharmacy's marker (one that isn't the initially-focused one) never
  // updated this cached value — so the directions button kept pointing
  // at the original pharmacy no matter which marker was actually
  // tapped. Now a live getter derived from _targetPharmacy below, so it
  // can never go stale after a tap — pharmacy coordinates are already
  // directly available on the order, no async resolution needed the
  // way the customer pin sometimes requires.
  LatLng? get _pharmacyDestination {
    final p = _targetPharmacy;
    if (p != null && p.hasCoords) return LatLng(p.lat!, p.lng!);
    return null;
  }
  LatLng? _customerDestination;
  bool _loadingDestination = true;
  String? _destError;
  BitmapDescriptor? _pharmacyIcon;
  final _orderRepo = OrderRepository();
  // CLIENT-REPORTED (2026-08-18): the "Open in Google Maps" button always
  // targeted the customer's map_link regardless of which marker was
  // actually tapped/showing — tapping the pharmacy's info window and
  // then hitting the button would still direct to the customer. Tracks
  // whichever destination the driver last tapped, defaulting to
  // whichever is operationally relevant right now (same priority the
  // camera already uses).
  _DestinationKind? _selectedDestination;
  // CLIENT-REPORTED (2026-08-22): for a multi-pharmacy order, tapping
  // any pharmacy marker OTHER than the initially-focused one had no
  // effect at all — there was no way to track "the driver just tapped
  // a different pharmacy" separately from the id the screen opened
  // with. This takes priority over widget.focusPharmacySellerId once set.
  int? _tappedPharmacySellerId;
  // Same crash fix as _HomeMapState in home_screen.dart — dispose() must
  // never call context.read() fresh; capture the reference once here,
  // in didChangeDependencies (guaranteed valid/active context), and use
  // only that stored reference in dispose().
  MapViewModel? _mapVM;

  @override
  void initState() {
    super.initState();
    _resolveDestination();
    // CLIENT-REQUESTED: show pharmacy pickup location(s) on the map too,
    // not just the customer destination — an order can have multiple.
    PharmacyMarkerIcon.get().then((icon) { if (mounted) setState(() => _pharmacyIcon = icon); });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<MapViewModel>();
    if (_mapVM != vm) {
      _mapVM = vm;
      vm.startTracking();
    }
  }

  // CLIENT-REPORTED (2026-08-19): resolves to whichever pharmacy was
  // actually tapped (see widget.focusPharmacySellerId), falling back to
  // the order's default primary pharmacy when no specific one was
  // requested — e.g. when opened from Home's generic "Maps" button
  // rather than a specific pharmacy's own card.
  // CLIENT-REPORTED (2026-08-22): now also checks _tappedPharmacySellerId
  // first — an in-screen tap on any pharmacy marker takes priority over
  // whatever the screen was originally opened with.
  Pharmacy? get _targetPharmacy {
    final focusId = _tappedPharmacySellerId ?? widget.focusPharmacySellerId;
    if (focusId != null) {
      for (final p in widget.order.pharmacies) {
        if (p.sellerId == focusId) return p;
      }
    }
    return widget.order.primaryPharmacy;
  }

  Future<void> _resolveDestination() async {
    final o = widget.order;
    // Pharmacy pin — no resolution needed here anymore; _pharmacyDestination
    // is a live getter derived from _targetPharmacy (see its declaration
    // above), always reflecting whichever pharmacy is currently selected.
    // Customer pin — same priority chain as before (lat/lng > map_link >
    // geocode), now always attempted rather than being skipped while
    // heading to pharmacy.
    final hasRealPin = !(o.pinPos.leftFraction == 0.5 && o.pinPos.topFraction == 0.5);
    if (hasRealPin) {
      setState(() {
        _customerDestination = LatLng(o.pinPos.topFraction, o.pinPos.leftFraction); // topFraction=lat, leftFraction=lng
        _loadingDestination = false;
      });
      return;
    }
    // No lat/lng, but a map_link is already a complete, reliable answer
    // on its own — it's a human-verified location, not a guess. Try to
    // resolve it to a real pin (see OrderRepository.resolveMapLinkCoords
    // — moved there so distance calculations elsewhere can reuse it
    // too, not just this map screen); if that doesn't work for any
    // reason, still never show a "not located" error here — the "Open
    // in Google Maps" button below always works regardless, since it
    // doesn't depend on this resolving.
    if (o.mapLink != null) {
      final result = await _orderRepo.resolveMapLinkCoords(o.mapLink!);
      if (!mounted) return;
      if (result != null) {
        setState(() { _customerDestination = LatLng(result.lat, result.lng); _loadingDestination = false; });
        _fitBounds();
      } else {
        setState(() { _loadingDestination = false; });
      }
      return;
    }
    // Only reach here when there's neither lat/lng nor a map_link —
    // now it's actually worth trying /geocode/{co} and showing an error
    // if that fails too. Note: a customer-address failure here no longer
    // means a totally blank map — the pharmacy pin (if any) still shows.
    try {
      final co = o.co ?? o.id;
      final result = await _orderRepo.geocodeOrder(co);
      if (!mounted) return;
      // Only suppress this error when the pharmacy is what's actually
      // relevant right now (heading there/collecting) — if the driver's
      // already heading to the patient, a failed customer geocode is a
      // real problem worth surfacing even if a (now-irrelevant) pharmacy
      // pin happens to still be sitting on the map from earlier.
      final pharmacyCoversIt = _targetPharmacy != null && o.isHeadingToPharmacy;
      if (result == null) {
        setState(() {
          _destError = pharmacyCoversIt ? null : "This order's address hasn't been located yet.";
          _loadingDestination = false;
        });
      } else {
        setState(() {
          _customerDestination = LatLng(result.lat, result.lng);
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
      final pharmacyCoversIt = _targetPharmacy != null && o.isHeadingToPharmacy;
      setState(() {
        _destError = pharmacyCoversIt ? null : 'Map error from server: ${e.message}';
        _loadingDestination = false;
      });
    } catch (_) {
      if (!mounted) return;
      final pharmacyCoversIt = _targetPharmacy != null && o.isHeadingToPharmacy;
      setState(() {
        _destError = pharmacyCoversIt ? null : "Couldn't locate this address on the map.";
        _loadingDestination = false;
      });
    }
  }

  // CLIENT-ASKED (2026-08-25): _resolveMapLinkCoords moved to
  // OrderRepository.resolveMapLinkCoords so distance calculations
  // elsewhere (home_screen.dart, order_detail_screen.dart) can reuse
  // the exact same logic instead of duplicating it — see the call site
  // above in _resolveDestination.

  void _fitBounds() {
    final mapVM = context.read<MapViewModel>();
    final driver = mapVM.driverPosition;
    if (_controller == null) return;
    // Camera framing still prioritizes whichever point is operationally
    // relevant right now (pharmacy while heading there/collecting, else
    // customer) — both pins are drawn on the map regardless (see
    // build() below), this just decides what the camera actually zooms
    // to, same reasoning as before this was split into two fields.
    final target = (widget.order.isHeadingToPharmacy ? _pharmacyDestination : _customerDestination)
        ?? _customerDestination ?? _pharmacyDestination;
    if (target == null) return;
    if (driver == null) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
      return;
    }
    // CLIENT-REPORTED: fitting the camera to include BOTH the driver and
    // the destination zooms out so far the destination pin becomes tiny
    // and hard to see whenever the two are genuinely far apart (e.g.
    // while testing, or before the driver has actually started heading
    // there). The destination is what the driver actually needs to see
    // clearly — only widen the view to include the driver's position
    // too when they're close enough for that to still be useful (normal
    // in-city delivery range); otherwise just zoom straight to the
    // destination and leave the driver marker wherever it falls.
    final distanceMeters = Geolocator.distanceBetween(
      driver.latitude, driver.longitude, target.latitude, target.longitude,
    );
    const closeEnoughMeters = 15000; // ~15km — normal in-city delivery range
    if (distanceMeters > closeEnoughMeters) {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
      return;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(
        driver.latitude < target.latitude ? driver.latitude : target.latitude,
        driver.longitude < target.longitude ? driver.longitude : target.longitude,
      ),
      northeast: LatLng(
        driver.latitude > target.latitude ? driver.latitude : target.latitude,
        driver.longitude > target.longitude ? driver.longitude : target.longitude,
      ),
    );
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  _DestinationKind get _effectiveSelection {
    if (_selectedDestination != null) return _selectedDestination!;
    // No explicit tap yet — default to whichever is operationally
    // relevant right now, same priority the camera already uses.
    return widget.order.isHeadingToPharmacy ? _DestinationKind.pharmacy : _DestinationKind.customer;
  }

  /// A real Google Maps DIRECTIONS url (turn-by-turn navigation from the
  /// driver's current location), not just a pin-drop, for whichever
  /// destination is currently selected. Falls back to an address-text
  /// query if coordinates for that destination aren't available, or to
  /// the raw map_link (still better than nothing) as a last resort for
  /// the customer specifically.
  String? get _directionsUrlForSelection {
    if (_effectiveSelection == _DestinationKind.pharmacy) {
      if (_pharmacyDestination != null) {
        return 'https://www.google.com/maps/dir/?api=1&destination='
            '${_pharmacyDestination!.latitude},${_pharmacyDestination!.longitude}&travelmode=driving';
      }
      final addr = _targetPharmacy?.address;
      if (addr != null && addr.isNotEmpty) {
        return 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(addr)}&travelmode=driving';
      }
      return null;
    }
    if (_customerDestination != null) {
      return 'https://www.google.com/maps/dir/?api=1&destination='
          '${_customerDestination!.latitude},${_customerDestination!.longitude}&travelmode=driving';
    }
    if (widget.order.mapLink != null) return widget.order.mapLink;
    if (widget.order.addr1.isNotEmpty) {
      return 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(widget.order.addr1)}&travelmode=driving';
    }
    return null;
  }

  String get _directionsLabelForSelection => _effectiveSelection == _DestinationKind.pharmacy
      ? 'Directions to ${_targetPharmacy?.name ?? "pharmacy"}'
      : 'Directions to ${widget.order.patient.isNotEmpty ? widget.order.patient : "customer"}';

  @override
  Widget build(BuildContext context) {
    final mapVM = context.watch<MapViewModel>();
    final driver = mapVM.driverPosition;

    final markers = <Marker>{
      if (_customerDestination != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: _customerDestination!,
          icon: BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(title: widget.order.patient, snippet: widget.order.addr1),
          onTap: () => setState(() => _selectedDestination = _DestinationKind.customer),
        ),
      if (_pharmacyDestination != null && _targetPharmacy != null)
        Marker(
          markerId: MarkerId('pharmacy_${_targetPharmacy!.sellerId ?? _targetPharmacy!.name}'),
          position: _pharmacyDestination!,
          icon: _pharmacyIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: _targetPharmacy!.name,
            snippet: '${_targetPharmacy!.itemsCount} item${_targetPharmacy!.itemsCount == 1 ? '' : 's'}',
          ),
          onTap: () => setState(() => _selectedDestination = _DestinationKind.pharmacy),
        ),
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You'),
        ),
      // Any OTHER pharmacies beyond the focused one — that one already
      // has its own dedicated marker above, so it's always excluded
      // here to avoid a duplicate pin at the same spot.
      // CLIENT-REPORTED (2026-08-22): this loop had NO onTap handler at
      // all — tapping any of these pharmacies did nothing, so the
      // directions button kept pointing at whichever pharmacy the
      // screen opened with, no matter which marker was actually tapped.
      for (final p in widget.order.pharmacies)
        if (p.hasCoords && p != _targetPharmacy)
          Marker(
            markerId: MarkerId('pharmacy_${p.sellerId ?? p.name}'),
            position: LatLng(p.lat!, p.lng!),
            icon: _pharmacyIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: p.name, snippet: '${p.itemsCount} item${p.itemsCount == 1 ? '' : 's'}'),
            onTap: () => setState(() {
              _selectedDestination = _DestinationKind.pharmacy;
              _tappedPharmacySellerId = p.sellerId;
            }),
          ),
    };

    return Scaffold(
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: (widget.order.isHeadingToPharmacy ? _pharmacyDestination : _customerDestination)
                ?? _customerDestination ?? _pharmacyDestination ?? driver ?? MapViewModel.kuwaitCity,
            zoom: 14,
          ),
          markers: markers,
          myLocationEnabled: false, // we draw our own "You" marker above
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) {
            _controller = c;
            if (_customerDestination != null || _pharmacyDestination != null) _fitBounds();
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
        // Bottom "re-center" button — shifted up when the directions bar
        // below is present, so the two don't overlap.
        Positioned(
          right: 16,
          bottom: _directionsUrlForSelection != null ? 96 : 32,
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
        // Directions — CLIENT-REPORTED (2026-08-18): this used to always
        // target the customer's map_link regardless of which marker was
        // actually tapped — tapping the pharmacy's info window and then
        // hitting this button would still direct to the customer. Now
        // targets whichever marker was last tapped (defaulting to
        // whichever is operationally relevant right now), and uses a
        // real turn-by-turn directions URL instead of just a pin-drop.
        if (_directionsUrlForSelection != null)
          Positioned(
            left: 16, right: 16, bottom: 24,
            child: SafeArea(
              top: false,
              child: GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(_directionsUrlForSelection!);
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: WTheme.navy,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('🧭', style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 8),
                    Text(_directionsLabelForSelection, style: GoogleFonts.dmSans(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    // Same reasoning as _HomeMapState.dispose() in home_screen.dart —
    // tracking is now app-wide (started once in main.dart, stopped only
    // on logout), not tied to this specific screen's lifecycle.
    super.dispose();
  }
}
