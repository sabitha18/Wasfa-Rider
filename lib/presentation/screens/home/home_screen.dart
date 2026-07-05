import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onTabChange, required this.onOpenOrder, required this.onArrive});
  final ValueChanged<String> onTabChange;
  final ValueChanged<String> onOpenOrder;
  final ValueChanged<String> onArrive; // called with order id when swipe fires

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final appVM = context.watch<AppViewModel>();
    final ordersVM = context.watch<OrdersViewModel>();
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
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(200),
                child: _MapBg(
                  orders: ordersVM.orders,
                  onPinTap: (id) => ordersVM.switchActive(id),
                ),
              ),
            ),
            // FABs
            Positioned(
              top: 16, right: 14,
              child: _fab(icon: Icons.my_location, onTap: () {}),
            ),
            Positioned(
              top: 80, right: 14,
              child: _fab(icon: Icons.sos, color: WTheme.err, iconColor: Colors.white, onTap: () {
                showWToast(context, '🆘 Emergency dispatched');
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
                    Flexible(child: Text('Tap any pin to make it stop #1',
                        style: GoogleFonts.dmSans(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4))),
                  ]),
                ),
              ),
            // Active order card — always fully expanded, matches HTML
            if (active != null)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: _ActiveOrderCard(
                  order: active,
                  onOpen: () => widget.onOpenOrder(active.id),
                  onArrive: () {
                    ordersVM.transitionDriverState(active.id, DriverState.onMyWay);
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

// ── Stylized map background — recreates the HTML's MapBg exactly ──
// Grid pattern + diagonal "roads" + pulsing rider dot + teardrop pins,
// positioned via each order's pinPos (left/top fractions of the viewport).
class _MapBg extends StatefulWidget {
  const _MapBg({required this.orders, required this.onPinTap});
  final List<Order> orders;
  final ValueChanged<String> onPinTap;

  @override
  State<_MapBg> createState() => _MapBgState();
}

class _MapBgState extends State<_MapBg> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color _pinColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.done: return WTheme.ok;
      case OrderStatus.active: return WTheme.rose;
      case OrderStatus.next: return WTheme.navy;
      case OrderStatus.later: return WTheme.sky;
      case OrderStatus.failed: return WTheme.err;
      default: return WTheme.sky;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return Stack(children: [
        // Base background
        Container(color: const Color(0xFFF1F6FA)),
        // Grid lines
        CustomPaint(size: Size(w, h), painter: _GridPainter()),
        // Diagonal "roads"
        Positioned(
          top: h * 0.15, left: -w * 0.05, right: -w * 0.05,
          child: Transform.rotate(
            angle: -3 * 3.1415926 / 180,
            child: Container(
              height: 12,
              decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 0, spreadRadius: 1)]),
            ),
          ),
        ),
        Positioned(
          top: h * 0.55, left: -w * 0.05, right: -w * 0.05,
          child: Transform.rotate(
            angle: 2 * 3.1415926 / 180,
            child: Container(
              height: 12,
              decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 0, spreadRadius: 1)]),
            ),
          ),
        ),
        Positioned(
          top: h * 0.10, bottom: h * 0.30, left: w * 0.30,
          child: Transform.rotate(
            angle: 4 * 3.1415926 / 180,
            child: Container(
              width: 12,
              decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 0, spreadRadius: 1)]),
            ),
          ),
        ),
        // Rider self — pulsing aqua dot (no Opacity widget — avoids dark compositing layer on Android)
        Positioned(
          left: w * 0.5 - 50, top: h * 0.35 - 50,
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, _) {
              final t = _pulseCtrl.value;
              return CustomPaint(
                size: const Size(100, 100),
                painter: _RiderDotPainter(
                  aqua: WTheme.aqua,
                  ringOpacity: (1 - t).clamp(0.0, 1.0),
                  ringRadius: (11 + (32 * t)).clamp(0.0, 50.0),
                ),
              );
            },
          ),
        ),
        // Order pins — teardrop shape via 45° rotated rounded square
        ...widget.orders.where((o) => o.status != OrderStatus.done && o.status != OrderStatus.failed).map((o) {
          final isActive = o.status == OrderStatus.active;
          final size = isActive ? 40.0 : 30.0;
          final left = w * o.pinPos.leftFraction - size / 2;
          final top = h * o.pinPos.topFraction - size / 2;
          return Positioned(
            left: left, top: top,
            child: GestureDetector(
              onTap: !isActive ? () => widget.onPinTap(o.id) : null,
              child: Transform.rotate(
                angle: -45 * 3.1415926 / 180,
                child: Container(
                  width: size, height: size,
                  decoration: BoxDecoration(
                    color: _pinColor(o.status),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(size / 2),
                      topRight: Radius.circular(size / 2),
                      bottomLeft: Radius.circular(size / 2),
                      bottomRight: Radius.zero,
                    ),
                    boxShadow: isActive
                        ? [
                      BoxShadow(color: WTheme.rose.withOpacity(0.5), blurRadius: 18, offset: const Offset(0, 6)),
                    ]
                        : [BoxShadow(color: WTheme.navy.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: 45 * 3.1415926 / 180,
                      child: Text('${o.stopNumber}',
                          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        // Also show done pins (checkmark)
        ...widget.orders.where((o) => o.status == OrderStatus.done).map((o) {
          const size = 30.0;
          final left = w * o.pinPos.leftFraction - size / 2;
          final top = h * o.pinPos.topFraction - size / 2;
          return Positioned(
            left: left, top: top,
            child: Transform.rotate(
              angle: -45 * 3.1415926 / 180,
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: WTheme.ok,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(size / 2),
                    topRight: Radius.circular(size / 2),
                    bottomLeft: Radius.circular(size / 2),
                    bottomRight: Radius.zero,
                  ),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: 45 * 3.1415926 / 180,
                    child: const Text('✓', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ),
              ),
            ),
          );
        }),
      ]);
    });
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WTheme.navy.withOpacity(0.06)
      ..strokeWidth = 1;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Draws the rider dot + pulsing ring entirely in canvas — no Opacity widget,
// no Border widget, no transparent Container — zero compositing artifacts on Android.
class _RiderDotPainter extends CustomPainter {
  const _RiderDotPainter({
    required this.aqua,
    required this.ringOpacity,
    required this.ringRadius,
  });
  final Color aqua;
  final double ringOpacity;
  final double ringRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Pulse ring — drawn first (behind dot)
    if (ringOpacity > 0) {
      canvas.drawCircle(
        center,
        ringRadius,
        Paint()
          ..color = aqua.withOpacity(ringOpacity * 0.45)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // White border circle
    canvas.drawCircle(center, 15, Paint()..color = Colors.white);

    // Aqua fill dot
    canvas.drawCircle(center, 11, Paint()..color = aqua);
  }

  @override
  bool shouldRepaint(_RiderDotPainter old) =>
      old.ringOpacity != ringOpacity || old.ringRadius != ringRadius;
}

class _ActiveOrderCard extends StatefulWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.onOpen,
    required this.onArrive,
  });
  final Order order;
  final VoidCallback onOpen, onArrive;

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
                        Text('KM', style: GoogleFonts.dmSans(fontSize: 9, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                // Quick actions
                Row(children: [
                  Expanded(child: QuickActionBtn(emoji: '🗺', label: 'Maps', color: const Color(0xFF4285F4), onTap: () => _openMaps(order))),
                  const SizedBox(width: 8),
                  Expanded(child: QuickActionBtn(emoji: '🚗', label: 'Waze', color: const Color(0xFF33CCFF), onTap: () => _openWaze(order))),
                  const SizedBox(width: 8),
                  Expanded(child: QuickActionBtn(emoji: '📞', label: 'Call', color: WTheme.ok, onTap: () => _call(order.phone))),
                ]),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          // Swipe control — always visible, whether collapsed or expanded
          SwipeToConfirm(label: 'Swipe when arrived', color: WTheme.rose, onConfirm: widget.onArrive),
        ],
      ),
    );
  }

  void _openMaps(Order o) async {
    final q = Uri.encodeComponent('${o.addr1}, ${o.addr2}, Kuwait');
    final url = 'https://www.google.com/maps/search/?api=1&query=$q';
    if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
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
        Text('All done!', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 20, color: WTheme.navy)),
        const SizedBox(height: 4),
        Text('No more active stops. Waiting for new orders…', style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.muted), textAlign: TextAlign.center),
      ]),
    );
  }
}
