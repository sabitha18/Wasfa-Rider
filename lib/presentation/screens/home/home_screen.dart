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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onTabChange, required this.onOpenOrder, required this.onArrive, required this.onOpenMap});
  final ValueChanged<String> onTabChange;
  final ValueChanged<String> onOpenOrder;
  final ValueChanged<String> onArrive; // called with order id when swipe fires
  final ValueChanged<Order> onOpenMap; // opens the in-app map for this order

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
                if (mounted) showWToast(context, 'Orders refreshed');
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
  final Set<String> _requested = {};     // orderIds already geocoded (or attempted)
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    context.read<MapViewModel>().startTracking();
    _geocodeVisibleOrders();
  }

  @override
  void didUpdateWidget(covariant _HomeMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _geocodeVisibleOrders(); // pick up any newly-added stops (e.g. accepted batch)
  }

  void _geocodeVisibleOrders() {
    for (final o in widget.orders) {
      if (o.status == OrderStatus.failed) continue;
      if (_requested.contains(o.id)) continue;
      _requested.add(o.id);
      _resolveOrder(o);
    }
  }

  Future<void> _resolveOrder(Order o) async {
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
    context.read<MapViewModel>().stopTracking();
    super.dispose();
  }
}

class _ActiveOrderCard extends StatefulWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.onOpen,
    required this.onArrive,
    required this.onOpenMap,
  });
  final Order order;
  final VoidCallback onOpen, onArrive;
  final ValueChanged<Order> onOpenMap;

  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard> {
  bool _expanded = true;

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
                Text('#${order.id}', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 20, color: WTheme.navy, letterSpacing: -0.4)),
                const SizedBox(height: 3),
                Row(children: [
                  const Text('👤', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(order.patient, style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w600)),
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
                // Address block
                GestureDetector(
                  onTap: widget.onOpen,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [WTheme.rose.withOpacity(0.06), WTheme.blush],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border(left: BorderSide(color: WTheme.rose, width: 4)),
                    ),
                    child: Row(children: [
                      Text('📍', style: TextStyle(color: WTheme.rose, fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(order.addr1, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 17, color: WTheme.navy, letterSpacing: -0.3)),
                        const SizedBox(height: 3),
                        Text(order.addr2, style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.ink, fontWeight: FontWeight.w600)),
                        if (order.landmark != null) ...[
                          const SizedBox(height: 4),
                          Text('· ${order.landmark}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontStyle: FontStyle.italic)),
                        ],
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${order.distanceKm}', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 16, color: WTheme.navy)),
                        Text(context.tr('km'), style: GoogleFonts.dmSans(fontSize: 9, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // Quick actions
                Row(children: [
                  Expanded(child: QuickActionBtn(emoji: '🗺', label: context.tr('maps'), color: const Color(0xFF4285F4), onTap: () => widget.onOpenMap(order))),
                  const SizedBox(width: 8),
                  Expanded(child: QuickActionBtn(emoji: '🚗', label: context.tr('waze'), color: const Color(0xFF33CCFF), onTap: () => _openWaze(order))),
                  const SizedBox(width: 8),
                  Expanded(child: QuickActionBtn(emoji: '📞', label: context.tr('call'), color: WTheme.ok, onTap: () => _call(order.phone))),
                ]),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          // Swipe control — always visible, whether collapsed or expanded
          SwipeToConfirm(label: context.tr('swipeArrived'), color: WTheme.rose, onConfirm: widget.onArrive),
        ],
      ),
    );
  }

  void _openWaze(Order o) async {
    final q = Uri.encodeComponent('${o.addr1}, Kuwait');
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
