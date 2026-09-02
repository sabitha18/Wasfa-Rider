import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/data/repositories/order_repository.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/map_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';

/// CLIENT-REQUESTED (2026-08-18): backend's own distance_km field has
/// been null on every single order response seen live so far, so
/// order.distanceKm always shows as a static 0. This computes a real,
/// live, continuously-updating STRAIGHT-LINE distance from the driver's
/// actual GPS position instead — not a true driving-route distance
/// (that needs the Directions API, a paid Google Cloud API whose key
/// shouldn't be embedded directly in the app, or backend finally
/// populating distance_km itself), but a genuine number that updates as
/// the driver moves, rather than a permanent placeholder zero.
// CLIENT-REPORTED (2026-08-22): moved to shared_widgets.dart as a public
// haversineKm() so order_detail_screen.dart can use the same real
// distance calculation instead of duplicating this math — that screen's
// own header had the identical "always 0.0 km" bug this originally fixed.

/// Accumulator for pharmacyAgg in _HomeMapState.build — holds the item
/// count from whichever order currently "wins" for this pharmacy (the
/// active order if it references this pharmacy, otherwise the lowest
/// stop number among the rest) — see the preference logic in build().
class _PharmacyAgg {
  final String name;
  final LatLng pos;
  final int itemsCount;
  final bool isActive;
  final int stopNumber;
  _PharmacyAgg(this.name, this.pos, this.itemsCount, this.isActive, this.stopNumber);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onTabChange,
    required this.onOpenOrder,
    required this.onArrive,
    required this.onOpenMap,
    required this.onOpenMapForPharmacy,
    required this.onTransitionState,
    required this.onMultiPickup,
  });
  final ValueChanged<String> onTabChange;
  final ValueChanged<String> onOpenOrder;
  final ValueChanged<String> onArrive; // called with order id once the FINAL "arrived" swipe fires
  final ValueChanged<Order> onOpenMap; // opens the in-app map for this order
  // CLIENT-REPORTED (2026-08-22): the "Maps" quick action always opened
  // the map for "the order" generically, which defaults to
  // order.primaryPharmacy — for a multi-pharmacy order, once the first
  // pharmacy was picked up, this kept pointing at that same (now done)
  // pharmacy instead of the next one still needing a visit.
  final void Function(Order order, Pharmacy pharmacy) onOpenMapForPharmacy;
  // Same driver-state sequence as OrderDetailScreen's _DriverActionBar —
  // the Home map card must walk pending -> collecting -> pickedUp -> onMyWay
  // too, not jump straight to "swipe when arrived".
  final void Function(String id, DriverState state) onTransitionState;
  final VoidCallback onMultiPickup;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<_HomeMapState> _mapKey = GlobalKey<_HomeMapState>();

  @override
  Widget build(BuildContext context) {
    final appVM = context.watch<AppViewModel>();
    final ordersVM = context.watch<OrdersViewModel>();
    final mapVM = context.watch<MapViewModel>();
    final driver = appVM.driver;
    final active = ordersVM.activeOrder;
    final hasMultipleStops = ordersVM.orders
        .where((o) => [OrderStatus.next, OrderStatus.later, OrderStatus.batchPending].contains(o.status))
        .isNotEmpty;

    // REMOVED (2026-08-25): this used to trigger MapViewModel's
    // live-location-sharing timer, which called a guessed endpoint
    // confirmed to be a genuine 404 — see MapViewModel's own note on
    // this. Removed here along with the feature itself.

    return Scaffold(
      body: Column(children: [
        RiderRibbon(
          earnings: driver?.todayEarnings ?? 0,
          deliveries: driver?.deliveriesToday ?? 0,
          onShift: driver?.onShift ?? false,
          onToggleShift: appVM.toggleShift,
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: _HomeMap(
                key: _mapKey,
                orders: ordersVM.orders,
                onPinTap: (id) => ordersVM.switchActive(id),
              ),
            ),
            // FABs
            Positioned(
              top: 16, right: 14,
              child: _fab(icon: Icons.my_location, onTap: () => _mapKey.currentState?.recenter()),
            ),
            Positioned(
              top: 80, right: 14,
              child: _fab(icon: Icons.sos, color: WTheme.err, iconColor: Colors.white, onTap: () {
                showWToast(context, context.tr('emergencyDispatched'));
              }),
            ),
            Positioned(
              top: 144, right: 14,
              child: _fab(icon: Icons.refresh, onTap: () async {
                await ordersVM.refresh();
                if (!mounted) return;
                // load() catches its own exceptions and never rethrows, so
                // this must check the error field explicitly — otherwise
                // this "refreshed" toast would show even on a genuine
                // failure, right alongside the separate red error banner.
                showWToast(context, ordersVM.error == null ? 'Orders refreshed' : "Couldn't refresh — check your connection");
              }),
            ),
            // Tap-pin hint
            if (hasMultipleStops)
              Positioned(
                top: 16, left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: const BoxConstraints(maxWidth: 220),
                  decoration: BoxDecoration(
                    color: WTheme.navy.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('📌', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Flexible(child: Text(context.tr('tapPinHint'),
                        style: GoogleFonts.dmSans(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
                  ]),
                ),
              ),
            // Location error banner — only appears if GPS/permission actually
            // failed (denied, disabled, etc.), surfaced from MapViewModel.error
            // instead of silently leaving the rider dot missing.
            if (mapVM.error != null)
              Positioned(
                top: hasMultipleStops ? 58 : 16, left: 14, right: 80,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: WTheme.err.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.3), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Text(mapVM.error!,
                      style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            // TEST-ONLY safeguard — impossible-to-miss badge so a faked
            // driver location can never accidentally ship in a client build.
            // Remove this whole block once kDebugFakeDriverLocation is gone.
            if (mapVM.isFakingLocation)
              Positioned(
                bottom: 100, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: const Text('🧪 TEST LOCATION ACTIVE — remove before release',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            // Active order card — always fully expanded, matches HTML
            if (active != null)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _ActiveOrderCard(
                  order: active,
                  onOpen: () => widget.onOpenOrder(active.id),
                  onOpenMap: widget.onOpenMap,
                  onOpenMapForPharmacy: widget.onOpenMapForPharmacy,
                  onTransitionState: widget.onTransitionState,
                  onMultiPickup: widget.onMultiPickup,
                  onArrive: () {
                    ordersVM.arriveAtPatient(active.id);
                    final id = active.id;
                    Future.microtask(() => widget.onArrive(id));
                  },
                ),
              ),
            if (active == null)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _AllDoneCard(),
              ),
          ]),
        ),
        RiderBottomNav(current: 'home', onChanged: widget.onTabChange),
      ]),
    );
  }

  Widget _fab({required IconData icon, VoidCallback? onTap,
    Color color = Colors.white, Color iconColor = WTheme.navy}) {
    return GestureDetector(
      onTap: onTap,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: Colors.black38,
        child: SizedBox(
          width: 48, height: 48,
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}

// ── Live map — real Google Map with the rider's actual GPS position and
// each stop's real address pin (resolved via GET /geocode/{co}), replacing
// the old stylized grid illustration. The client needs the rider's real
// location shown, not a mock background.
//
// Order pins here come from the same on-demand geocode endpoint the
// full-screen InAppMapScreen uses — Order.pinPos (left/top fractions) was
// only ever meant for the old fake map and has no relation to real
// coordinates, so it's not used for placement anymore.
class _HomeMap extends StatefulWidget {
  const _HomeMap({super.key, required this.orders, required this.onPinTap});
  final List<Order> orders;
  final ValueChanged<String> onPinTap;

  @override
  State<_HomeMap> createState() => _HomeMapState();
}

class _HomeMapState extends State<_HomeMap> {
  GoogleMapController? _controller;
  final _orderRepo = OrderRepository();
  final Map<String, LatLng> _pins = {};  // orderId -> resolved coordinate
  final Set<String> _requested = {};     // "orderId:isHeadingToPharmacy" keys already resolved (or attempted)
  bool _didInitialFit = false;
  // CLIENT-REPORTED CRASH: dispose() was calling context.read<MapViewModel>()
  // directly, which threw "Looking up a deactivated widget's ancestor is
  // unsafe" — this widget can be torn down as part of a larger unmount
  // (e.g. the whole app screen swapping away quickly), by which point its
  // context is no longer safe to walk up from. Capture the reference here
  // in didChangeDependencies instead (guaranteed to run with a valid,
  // active context) and use ONLY this stored reference in dispose(),
  // never a fresh context.read() at that point.
  MapViewModel? _mapVM;
  BitmapDescriptor? _pharmacyIcon;

  @override
  void initState() {
    super.initState();
    _geocodeVisibleOrders();
    // CLIENT-REQUESTED: show pharmacy pickup location(s) on the Home map
    // too, not just the customer/destination pins.
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

  @override
  void didUpdateWidget(covariant _HomeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _geocodeVisibleOrders(); // pick up any newly-added stops (e.g. accepted batch)
  }

  void _geocodeVisibleOrders() {
    for (final o in widget.orders) {
      if (o.status == OrderStatus.failed) continue;
      // CLIENT-REPORTED (2026-08-18): keyed on order id alone before, so
      // an order's pin — once resolved to the customer's address — never
      // got a chance to switch to the pharmacy's location even after
      // transitioning into heading-to-pharmacy/collecting. Keying on
      // phase too means a transition triggers a fresh resolution.
      final key = '${o.id}:${o.isHeadingToPharmacy}';
      if (_requested.contains(key)) continue;
      _requested.add(key);
      _resolveOrder(o);
    }
  }

  Future<void> _resolveOrder(Order o) async {
    // The pin for THIS order on the inline map — resolve to the
    // pharmacy's own coordinates while heading there/collecting, same
    // priority InAppMapScreen already uses for the full "Maps" screen.
    // Previously this always geocoded the CUSTOMER's address regardless
    // of phase, showing the wrong location during pharmacy pickup.
    final pharmacy = o.nextUnpickedPharmacy;
    if (o.isHeadingToPharmacy && pharmacy != null && pharmacy.hasCoords) {
      setState(() => _pins[o.id] = LatLng(pharmacy.lat!, pharmacy.lng!));
      return;
    }
    try {
      final result = await _orderRepo.geocodeOrder(o.co ?? o.id);
      if (!mounted || result == null) {
        debugPrint('[HomeMap] geocode for order ${o.id} (co=${o.co}) returned null — no pin will show');
        return;
      }
      debugPrint('[HomeMap] geocode for order ${o.id} (co=${o.co}) -> lat=${result.lat}, lng=${result.lng}');
      setState(() => _pins[o.id] = LatLng(result.lat, result.lng));
    } catch (e) {
      // Background enhancement only — if a stop's address can't be
      // geocoded it just won't get a pin here; it's still reachable from
      // the order detail screen / its own quick-action map button.
      debugPrint('[HomeMap] geocode FAILED for order ${o.id} (co=${o.co}): $e');
    }
  }

  double _pinHue(OrderStatus s) {
    switch (s) {
      case OrderStatus.active: return BitmapDescriptor.hueRose;
      case OrderStatus.next: return BitmapDescriptor.hueViolet;
      case OrderStatus.later: return BitmapDescriptor.hueCyan;
      case OrderStatus.done: return BitmapDescriptor.hueGreen;
      default: return BitmapDescriptor.hueOrange;
    }
  }

  /// Re-centers on the driver's current live position — wired to the
  /// "my location" FAB in HomeScreen.
  void recenter() {
    final driver = context.read<MapViewModel>().driverPosition;
    if (_controller == null || driver == null) return;
    _controller!.animateCamera(CameraUpdate.newLatLngZoom(driver, 15));
  }

  @override
  Widget build(BuildContext context) {
    final driver = context.watch<MapViewModel>().driverPosition;

    // The moment we get a real GPS fix, snap the camera to it once rather
    // than sitting on the default Kuwait-city fallback center.
    if (driver != null && !_didInitialFit && _controller != null) {
      _didInitialFit = true;
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(driver, 15));
    }

    // CLIENT-REPORTED (2026-08-18): confirmed live — a pharmacy marker
    // showed "1 item" when the order actually being worked on needed 2
    // from that same pharmacy. First attempt at fixing this summed
    // items_count across every order sharing that pharmacy — wrong
    // call, since that produces a total unrelated to any single order
    // (e.g. "6 items" when the active order only needs 2), which is
    // arguably more confusing than the original bug. What's actually
    // wanted: the marker should match whatever the swipe card ALREADY
    // correctly shows for the order the driver is currently working on.
    // Prefer the ACTIVE order's own item count for a shared pharmacy;
    // only fall back to another order's count (lowest stop number)
    // when the active order doesn't reference that pharmacy at all.
    final Map<String, _PharmacyAgg> pharmacyAgg = {};
    for (final o in widget.orders) {
      if (o.status == OrderStatus.failed) continue;
      for (final p in o.pharmacies) {
        if (!p.hasCoords) continue;
        final key = '${p.sellerId ?? p.name}';
        final existing = pharmacyAgg[key];
        final thisIsBetter = existing == null
            || (o.status == OrderStatus.active && existing.isActive != true)
            || (o.status != OrderStatus.active && existing.isActive != true && o.stopNumber < existing.stopNumber);
        if (thisIsBetter) {
          pharmacyAgg[key] = _PharmacyAgg(p.name, LatLng(p.lat!, p.lng!), p.itemsCount, o.status == OrderStatus.active, o.stopNumber);
        }
      }
    }

    final markers = <Marker>{
      if (driver != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You'),
          zIndex: 2,
        ),
      for (final o in widget.orders)
        if (o.status != OrderStatus.failed && _pins[o.id] != null)
          Marker(
            markerId: MarkerId(o.id),
            position: _pins[o.id]!,
            icon: BitmapDescriptor.defaultMarkerWithHue(_pinHue(o.status)),
            infoWindow: InfoWindow(title: 'Stop ${o.stopNumber} — ${o.patient}', snippet: o.addr1),
            onTap: o.status == OrderStatus.active ? null : () => widget.onPinTap(o.id),
          ),
      // CLIENT-REQUESTED: pharmacy pickup location(s) for every visible
      // order — see pharmacyAgg above for why these are aggregated
      // across orders rather than built one-per-order.
      for (final entry in pharmacyAgg.entries)
        Marker(
          markerId: MarkerId('pharmacy_${entry.key}'),
          position: entry.value.pos,
          icon: _pharmacyIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: entry.value.name,
            snippet: '${entry.value.itemsCount} item${entry.value.itemsCount == 1 ? '' : 's'}',
          ),
        ),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: driver ?? MapViewModel.kuwaitCity,
        zoom: 14,
      ),
      markers: markers,
      myLocationEnabled: false, // we draw our own styled "You" marker above
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (c) => _controller = c,
    );
  }

  @override
  void dispose() {
    // CLIENT-REPORTED (2026-08-13): rapid Home <-> Orders <-> Profile
    // tab-switching made the app appear stuck. Root cause: tabs aren't a
    // persistent IndexedStack — main.dart fully disposes/rebuilds each
    // screen on every switch — so stopping tracking here meant every
    // single Home mount had to redo the full _ensurePermission()
    // native-channel round-trip in startTracking(), which can queue up
    // and visibly stall the UI when triggered many times in quick
    // succession. Tracking now starts once, app-wide, in main.dart's
    // one-time setup, and only stops on logout — not on every Home
    // dispose, since another screen (or the next Home mount seconds
    // later) will just need it again anyway.
    super.dispose();
  }
}

class _ActiveOrderCard extends StatefulWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.onOpen,
    required this.onArrive,
    required this.onOpenMap,
    required this.onOpenMapForPharmacy,
    required this.onTransitionState,
    required this.onMultiPickup,
  });
  final Order order;
  final VoidCallback onOpen, onArrive, onMultiPickup;
  final ValueChanged<Order> onOpenMap;
  final void Function(Order order, Pharmacy pharmacy) onOpenMapForPharmacy;
  final void Function(String id, DriverState state) onTransitionState;

  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard> {
  bool _expanded = true;
  // CLIENT-REPORTED (2026-08-25): confirmed live — an order can have a
  // genuine, complete text address (addr1/addr2/addr_full all populated)
  // while its own lat/lng fields are null. The distance calculation
  // only ever checked the raw lat/lng, so it showed "No address on
  // file" — misleading wording, since the order genuinely DOES have an
  // address, just not coordinates for it yet.
  //
  // CLIENT-ASKED (2026-08-25) follow-up: what if lat/lng are missing
  // but map_link is present? A map_link is a human-verified location —
  // generally MORE reliable than geocoding a free-text address — so it
  // needs to be tried BEFORE geocoding, not skipped. Matches the exact
  // same "lat/lng > map_link > geocode" priority the map screens
  // already use (see OrderRepository.resolveMapLinkCoords).
  final _orderRepo = OrderRepository();
  final Map<String, LatLng?> _geocodedCustomerPins = {};
  final Set<String> _geocodeAttempted = {};

  LatLng? _resolveCustomerPin(Order order) {
    if (_geocodedCustomerPins.containsKey(order.id)) return _geocodedCustomerPins[order.id];
    if (_geocodeAttempted.contains(order.id)) return null;
    _geocodeAttempted.add(order.id);
    Future<({double lat, double lng})?> resolve() {
      if (order.mapLink != null) return _orderRepo.resolveMapLinkCoords(order.mapLink!);
      return _orderRepo.geocodeOrder(order.co ?? order.id);
    }
    resolve().then((result) {
      if (!mounted) return;
      setState(() => _geocodedCustomerPins[order.id] = result != null ? LatLng(result.lat, result.lng) : null);
    });
    return null;
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  void _onDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    // swipe down (positive velocity) -> collapse, swipe up (negative) -> expand
    if (v > 250 && _expanded) {
      setState(() => _expanded = false);
    } else if (v < -250 && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(18, 14, 18, _expanded ? 22 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.18), blurRadius: 36, offset: const Offset(0, -8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle — tap OR drag to toggle
          GestureDetector(
            onTap: _toggle,
            onVerticalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: Container(
                  width: 44, height: 4,
                  decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Header row — always visible, also draggable/tappable
          GestureDetector(
            onTap: _toggle,
            onVerticalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.opaque,
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: WTheme.rose, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.rose.withOpacity(0.5), blurRadius: 14, offset: const Offset(0, 6))],
                ),
                child: Center(child: Text('${order.stopNumber}',
                    style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // CLIENT-REPORTED (2026-09-01): when the payment chip
                // shows its longer label ("GO TAP · NOT PAID"), it takes
                // up enough of this row's width that the order ID's
                // Expanded column gets squeezed narrow — and since this
                // Text had no overflow handling at all, it wrapped onto
                // an awkward second line instead of staying on one.
                // maxLines+ellipsis truncates cleanly instead.
                Text('#${order.id}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 20, color: WTheme.navy, letterSpacing: -0.4)),
                const SizedBox(height: 3),
                // CLIENT-REPORTED (2026-09-01) follow-up: the order ID
                // fix above wasn't the only overflow source on this row
                // — this patient-name Text had no overflow handling
                // either, and with no Expanded/Flexible around it, it
                // had no bounded width to even truncate against. Real,
                // confirmed RenderFlex overflow seen live ("RIGHT
                // OVERFLOWED BY 1.7 PIXELS") once the longer "GO TAP ·
                // NOT PAID" chip squeezed this row's remaining space.
                Row(children: [
                  const Text('👤', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(order.patient, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w600))),
                ]),
              ])),
              PayChip(method: order.payMethod, paid: order.paid),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 260),
                child: Icon(Icons.keyboard_arrow_up_rounded, color: WTheme.muted, size: 22),
              ),
            ]),
          ),

          // Collapsible content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(children: [
                // Address block — CLIENT-REQUESTED (2026-08-13): shows the
                // PHARMACY's pickup location while heading there/collecting
                // (steps 1-2), not the customer's address — that's not
                // where the driver needs to go yet. Switches back to the
                // customer automatically from pickedUp onward.
                Builder(builder: (context) {
                  // CLIENT-REPORTED (2026-08-22): once the first of
                  // several pharmacies was marked picked up, this card
                  // (and its Maps/Waze/Call buttons) kept showing that
                  // same first pharmacy forever, with the swipe button
                  // stuck on "Open pickup checklist" regardless of
                  // progress. nextUnpickedPharmacy correctly moves on to
                  // whichever pharmacy still needs collecting.
                  final showingPharmacy = order.isHeadingToPharmacy && order.nextUnpickedPharmacy != null;
                  final pharmacy = order.nextUnpickedPharmacy;
                  final accent = showingPharmacy ? const Color(0xFF2ECC71) : WTheme.rose;
                  // CLIENT-REPORTED (2026-08-22) follow-up: my previous
                  // fix only explained the "driver's own GPS missing"
                  // case — a bare, unexplained "—" (no km/min attempted
                  // at all) means driverPos is actually NON-null (GPS
                  // working), and destPos (the pharmacy/customer's own
                  // coordinates) is the missing piece instead, which
                  // this never distinguished. Now covers every case.
                  final mapVM = context.watch<MapViewModel>();
                  final driverPos = mapVM.driverPosition;
                  LatLng? destPos;
                  if (showingPharmacy && pharmacy!.hasCoords) {
                    destPos = LatLng(pharmacy.lat!, pharmacy.lng!);
                  } else if (!showingPharmacy) {
                    final hasRealPin = !(order.pinPos.leftFraction == 0.5 && order.pinPos.topFraction == 0.5);
                    // CLIENT-REPORTED (2026-08-25): confirmed live — an
                    // order can have a complete text address
                    // (addr1/addr2/addr_full all populated) while its
                    // own lat/lng fields are null. This used to just
                    // give up in that case, showing "No address on
                    // file" — misleading, since the address genuinely
                    // exists, just not geocoded yet. Falls back to
                    // resolving it the same way the map screens already
                    // do, via _resolveCustomerPin below.
                    destPos = hasRealPin
                        ? LatLng(order.pinPos.topFraction, order.pinPos.leftFraction)
                        : _resolveCustomerPin(order);
                  }
                  final live = liveDistanceAndEta(driverPos, destPos);
                  final liveDistanceKm = live.km;
                  final liveEtaMin = live.etaMin;
                  // Only the "driver's own GPS missing" case is
                  // something the driver can act on (retry/Settings) —
                  // a missing destination coordinate is a data problem
                  // backend needs to fix, and a rejected reading (both
                  // positions exist but the result was unrealistic)
                  // needs a fresh GPS fix, not a permission dialog.
                  final gpsIsActionable = driverPos == null;
                  // CLIENT-REPORTED (2026-08-25): reworded to be
                  // specific about what's actually missing — the order
                  // can genuinely have a full address on file, just no
                  // coordinates for it (yet, until geocoding resolves,
                  // or if it never can be geocoded at all).
                  final gpsStatusText = liveDistanceKm != null
                      ? null
                      : driverPos == null
                          ? (mapVM.error != null ? 'No GPS ↻' : 'GPS…')
                          : destPos == null
                              ? (showingPharmacy ? 'No pharmacy coords' : 'Locating address…')
                              : 'GPS unclear';
                  return GestureDetector(
                    onTap: widget.onOpen,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [accent.withOpacity(0.06), WTheme.blush],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border(left: BorderSide(color: accent, width: 4)),
                      ),
                      child: Row(children: [
                        Text(showingPharmacy ? '💊' : '📍', style: TextStyle(color: accent, fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (showingPharmacy) ...[
                            Row(children: [
                              Text('PHARMACY PICKUP', style: GoogleFonts.dmSans(
                                  fontSize: 10, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.5)),
                              // CLIENT-REPORTED (2026-08-18): this card
                              // only ever showed the FIRST pharmacy —
                              // an order with items from 2+ different
                              // pharmacies gave no indication a second
                              // stop existed at all. This card is too
                              // compact to show full details per
                              // pharmacy, so at minimum flag that more
                              // exist and point at the full checklist.
                              // CLIENT-REPORTED (2026-08-22): this
                              // counted total-1 regardless of picked
                              // status, so it kept showing "+1 MORE"
                              // even once only one pharmacy genuinely
                              // remained. Now counts remaining UNPICKED
                              // pharmacies specifically, excluding
                              // whichever one is currently shown above.
                              if (order.pharmacies.where((p) => !p.pickedUp).length > 1) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
                                  child: Text('+${order.pharmacies.where((p) => !p.pickedUp).length - 1} MORE', style: GoogleFonts.dmSans(
                                      fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 2),
                            Text(pharmacy!.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 17, color: WTheme.navy, letterSpacing: -0.3)),
                            const SizedBox(height: 2),
                            Text('${pharmacy.itemsCount} item${pharmacy.itemsCount == 1 ? '' : 's'}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: accent, fontWeight: FontWeight.w700)),
                            if (pharmacy.address != null) ...[
                              const SizedBox(height: 3),
                              Text(pharmacy.address!, style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.ink, fontWeight: FontWeight.w600)),
                            ],
                          ] else ...[
                            Text(order.addr1, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 17, color: WTheme.navy, letterSpacing: -0.3)),
                            const SizedBox(height: 3),
                            Text(order.addr2, style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.ink, fontWeight: FontWeight.w600)),
                            if (order.landmark != null) ...[
                              const SizedBox(height: 4),
                              Text('· ${order.landmark}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontStyle: FontStyle.italic)),
                            ],
                          ],
                        ])),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          if (liveDistanceKm != null) ...[
                            Text(
                              liveDistanceKm < 1 ? '${(liveDistanceKm * 1000).round()}' : liveDistanceKm.toStringAsFixed(1),
                              style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 16, color: WTheme.navy),
                            ),
                            Text(liveDistanceKm < 1 ? 'm' : context.tr('km'), style: GoogleFonts.dmSans(fontSize: 9, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                            if (liveEtaMin != null) ...[
                              const SizedBox(height: 2),
                              Text('~$liveEtaMin min', style: GoogleFonts.dmSans(fontSize: 10, color: accent, fontWeight: FontWeight.w800)),
                            ],
                          ] else
                            // CLIENT-REPORTED (2026-08-22): originally
                            // only explained "driver's own GPS missing"
                            // — a bare, unexplained "—" meant destPos
                            // (the pharmacy/customer's own coordinates)
                            // was the actual missing piece instead,
                            // which wasn't distinguished at all. Now
                            // covers every case (see gpsStatusText
                            // above) — only the driver-GPS case is
                            // actually tappable (retry/Settings); a
                            // missing destination coordinate is a data
                            // problem backend needs to fix, not
                            // something re-asking permission can solve.
                            GestureDetector(
                              onTap: gpsIsActionable ? () => mapVM.retryLocationPermission() : null,
                              child: Text(
                                gpsStatusText ?? '—',
                                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 11,
                                    color: gpsIsActionable && mapVM.error != null ? WTheme.rose : WTheme.muted,
                                    decoration: gpsIsActionable && mapVM.error != null ? TextDecoration.underline : null),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                // Quick actions — target the pharmacy while heading
                // there/collecting, the customer otherwise (see above).
                Row(children: [
                  Expanded(child: QuickActionBtn(emoji: '🗺', label: context.tr('maps'), color: const Color(0xFF4285F4), onTap: () {
                    final nextPharmacy = order.nextUnpickedPharmacy;
                    if (order.isHeadingToPharmacy && nextPharmacy != null) {
                      widget.onOpenMapForPharmacy(order, nextPharmacy);
                    } else {
                      widget.onOpenMap(order);
                    }
                  })),
                  const SizedBox(width: 8),
                  Expanded(child: QuickActionBtn(emoji: '🚗', label: context.tr('waze'), color: const Color(0xFF33CCFF), onTap: () => _openWaze(order))),
                  const SizedBox(width: 8),
                  Expanded(child: QuickActionBtn(emoji: '📞', label: context.tr('call'), color: WTheme.ok,
                      onTap: () => _call((order.isHeadingToPharmacy ? order.nextUnpickedPharmacy?.phone : null) ?? order.phone))),
                ]),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          // Step label + swipe control — always visible, whether collapsed
          // or expanded. Mirrors OrderDetailScreen's _DriverActionBar: an
          // "assigned" (pending) order must swipe through collecting ->
          // pickedUp -> onMyWay before "arrived" ever shows up here, same
          // as it already correctly does on the order-detail screen.
          _buildStepAndSwipe(context, order),
        ],
      ),
    );
  }

  Widget _buildStepAndSwipe(BuildContext context, Order order) {
    final ds = order.driverState;
    final String stepLabel, swipeLabel;
    final Color swipeColor, labelColor;
    final VoidCallback onConfirm;

    switch (ds) {
      case DriverState.pending:
        stepLabel = context.tr('step1Heading');
        swipeLabel = order.multiPharmacy
            ? context.tr('headingToFirstPharmacy')
            : context.tr('headingToPharmacy');
        swipeColor = WTheme.sky;
        labelColor = const Color(0xFF2A9BBC);
        onConfirm = () => widget.onTransitionState(order.id, DriverState.collecting);
      case DriverState.collecting:
        stepLabel = context.tr('step2Collecting');
        swipeLabel = order.multiPharmacy
            ? context.tr('openPickupChecklist')
            : context.tr('confirmPickedUp');
        swipeColor = WTheme.aqua;
        labelColor = WTheme.aqua;
        onConfirm = order.multiPharmacy
            ? () => Future.microtask(widget.onMultiPickup)
            // CLIENT-REPORTED (2026-09-02): confirmed live via logcat —
            // swiping through to "arrived at patient" on a single-
            // pharmacy order got rejected by backend's own /arrive
            // endpoint with 409 "Pick up from all pharmacies first"
            // ({"picked_count":0,"pharmacy_count":1}) — even though
            // driver_state had already reached onMyWay. Root cause: this
            // branch only ever called the generic status-update endpoint
            // (driver_state -> pickedUp), which backend accepts without
            // requiring pickup confirmation — but never actually called
            // the DEDICATED per-pharmacy pickup endpoint that increments
            // picked_count, the thing /arrive actually checks. Only the
            // multi-pharmacy flow ever called that correctly. Now calls
            // the same markPharmacyPickedUp used there, for this order's
            // one pharmacy — it already handles the driverState
            // transition to pickedUp internally once complete, so no
            // separate onTransitionState call is needed here anymore.
            : () {
                if (order.pharmacies.isNotEmpty) {
                  context.read<OrdersViewModel>().markPharmacyPickedUp(order.id, order.pharmacies.first);
                } else {
                  // Defensive fallback — should not happen for a real
                  // order, but avoids silently doing nothing if pharmacy
                  // data is ever missing for some reason.
                  widget.onTransitionState(order.id, DriverState.pickedUp);
                }
              };
      case DriverState.pickedUp:
        stepLabel = context.tr('step3ItemsInHand');
        swipeLabel = context.tr('headingToPatient');
        swipeColor = WTheme.rose;
        labelColor = WTheme.rose;
        onConfirm = () => widget.onTransitionState(order.id, DriverState.onMyWay);
      default: // onMyWay — the only state where "arrived" is correct
        stepLabel = context.tr('step4OnTheWay');
        swipeLabel = context.tr('swipeArrived');
        swipeColor = WTheme.rose;
        labelColor = WTheme.rose;
        onConfirm = widget.onArrive;
    }

    return Column(children: [
      Text(stepLabel.toUpperCase(), textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800,
              color: labelColor, letterSpacing: 0.6)),
      const SizedBox(height: 8),
      SwipeToConfirm(label: swipeLabel, color: swipeColor, onConfirm: onConfirm),
    ]);
  }

  void _openWaze(Order o) async {
    // CLIENT-REQUESTED (2026-08-13): route to the pharmacy while heading
    // there/collecting — falls back to the customer address if the
    // pharmacy has none rather than doing nothing.
    final target = (o.isHeadingToPharmacy ? o.nextUnpickedPharmacy?.address : null) ?? o.addr1;
    final q = Uri.encodeComponent('$target, Kuwait');
    final url = 'https://waze.com/ul?q=$q';
    if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
  }

  void _call(String phone) async {
    final url = 'tel:${phone.replaceAll(RegExp(r'\s'), '')}';
    if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
  }
}

class _AllDoneCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 24)],
      ),
      child: Column(children: [
        const Text('🎉', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(context.tr('allDone'), style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 20, color: WTheme.navy)),
        const SizedBox(height: 4),
        Text(context.tr('noMoreStops'), style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.muted), textAlign: TextAlign.center),
      ]),
    );
  }
}
