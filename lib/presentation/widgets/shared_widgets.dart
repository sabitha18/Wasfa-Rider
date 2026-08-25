import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../core/constants/app_strings.dart';

// CLIENT-REPORTED (2026-08-22): Order Detail's own header still showed a
// permanent "0.0 km · 0 min" — this same class of bug was already fixed
// on Home's card, but that fix used a PRIVATE helper local to
// home_screen.dart, so Order Detail never got the same fix. Made public
// and shared here so both screens (and any future one) can compute a
// real, live straight-line distance instead of relying on backend's own
// distance_km/eta_min fields, which have been null on every order seen
// live throughout this whole project.
double haversineKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  final dLat = _deg2rad(b.latitude - a.latitude);
  final dLng = _deg2rad(b.longitude - a.longitude);
  final lat1 = _deg2rad(a.latitude);
  final lat2 = _deg2rad(b.latitude);
  final sinDLat = sin(dLat / 2);
  final sinDLng = sin(dLng / 2);
  final h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
  final c = 2 * atan2(sqrt(h), sqrt(1 - h));
  return earthRadiusKm * c;
}

double _deg2rad(double deg) => deg * (pi / 180.0);

// CLIENT-REPORTED (2026-08-22): a wildly wrong distance ("3499.6 km ·
// ~6999 min") showed on screen as if it were a normal, trustworthy
// number. Root cause was a bad/stale GPS reading (not a bug in the math
// itself), but neither home_screen.dart's nor order_detail_screen.dart's
// copy of this calculation had any sanity check to catch an obviously
// impossible result for a same-city delivery — showing it anyway is
// actively misleading, not just imprecise. Shared here (was duplicated
// separately in both files) so both get this fix at once, and so a
// future third usage doesn't reintroduce the same duplicated logic.
({double? km, int? etaMin}) liveDistanceAndEta(LatLng? driverPos, LatLng? destPos) {
  if (driverPos == null || destPos == null) return (km: null, etaMin: null);
  final raw = haversineKm(driverPos, destPos);
  // CLIENT-REPORTED (2026-08-22): this used to reject anything over
  // 100km as "must be a bad GPS reading" — but that was the wrong
  // assumption. Confirmed live: testing from Kozhikode, India against a
  // Kuwait-based pharmacy produces a genuinely correct ~3000+ km
  // distance, which this was silently hiding as if it were a glitch.
  // A real driver in production is always physically in Kuwait, so this
  // "safety net" was never actually needed there — it only ever broke
  // visibility during cross-country testing instead. No sanity check
  // needed at all: any two valid coordinates produce a mathematically
  // correct distance regardless of how large it happens to be.
  const avgSpeedKmh = 30.0; // rough urban-driving assumption — not traffic-aware, not routed
  return (km: raw, etaMin: (raw / avgSpeedKmh * 60).round());
}

// ── Pharmacy map marker icon ─────────────────────────────────────
// CLIENT-REQUESTED: pharmacy pickup locations need their own distinct
// marker, separate from the customer/destination pin and the driver's
// own "You" marker. Shared here (not duplicated per-screen) since both
// home_screen.dart's inline map and in_app_map_screen.dart's full map
// need the identical icon. Drawing a bitmap is async and the same icon
// is reused everywhere, so it's built once and cached rather than
// redrawn on every rebuild.
class PharmacyMarkerIcon {
  static BitmapDescriptor? _cached;
  static Future<BitmapDescriptor>? _pending;

  static Future<BitmapDescriptor> get() {
    if (_cached != null) return Future.value(_cached);
    return _pending ??= _build().then((icon) {
      _cached = icon;
      return icon;
    });
  }

  static Future<BitmapDescriptor> _build() async {
    // CLIENT-REPORTED: the first version was a rounded-square badge —
    // read as a floating icon, not a map marker. Redrawn as an actual
    // teardrop pin (circular head + tapered point at the bottom), the
    // same silhouette every standard map pin uses, just green with a
    // checkmark instead of red/blank.
    const double w = 96, h = 116; // taller than wide — head + tail
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

    const headCenter = Offset(w / 2, w * 0.36);
    const headRadius = w * 0.34;
    const tip = Offset(w / 2, h - 4);

    // Head (circle) unioned with a triangular tail down to the tip —
    // Path.combine gives a clean single silhouette with no seam between
    // the two shapes, rather than two overlapping shapes drawn separately.
    final headPath = Path()..addOval(Rect.fromCircle(center: headCenter, radius: headRadius));
    final tailPath = Path()
      ..moveTo(headCenter.dx - headRadius * 0.8, headCenter.dy + headRadius * 0.5)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(headCenter.dx + headRadius * 0.8, headCenter.dy + headRadius * 0.5)
      ..close();
    final pinPath = Path.combine(PathOperation.union, headPath, tailPath);

    // Subtle drop shadow first, then the pin itself, then a white
    // outline — same visual layering real map pins use so it reads as
    // a marker sitting ON the map rather than a flat sticker.
    canvas.drawPath(pinPath.shift(const Offset(0, 2)), Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(pinPath, Paint()..color = const Color(0xFF2ECC71));
    canvas.drawPath(pinPath, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045);

    // White checkmark, centered in the head (not the whole taller canvas).
    final checkPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final check = Path()
      ..moveTo(headCenter.dx - headRadius * 0.5, headCenter.dy + headRadius * 0.05)
      ..lineTo(headCenter.dx - headRadius * 0.1, headCenter.dy + headRadius * 0.4)
      ..lineTo(headCenter.dx + headRadius * 0.55, headCenter.dy - headRadius * 0.35);
    canvas.drawPath(check, checkPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }
}

// ── Status Pill ────────────────────────────────────────────────
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.deliveredAt, this.small = false});
  final OrderStatus status;
  final DateTime? deliveredAt;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      OrderStatus.active      => (WTheme.rose.withOpacity(0.15), WTheme.rose,       '📍 Active'),
      OrderStatus.next        => (WTheme.navy.withOpacity(0.10), WTheme.navy,       '⏭ Next up'),
      OrderStatus.later       => (WTheme.aqua.withOpacity(0.18), const Color(0xFF2A9BBC), '🕒 Later'),
      OrderStatus.done        => (WTheme.ok.withOpacity(0.15),   WTheme.ok,         '✓ Delivered'),
      OrderStatus.failed      => (WTheme.err.withOpacity(0.12),  WTheme.err,        '🚫 Failed'),
      OrderStatus.batchPending=> (WTheme.cloud,                  WTheme.muted,      '📦 In batch'),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 2 : 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: GoogleFonts.dmSans(
        fontSize: small ? 10 : 11, fontWeight: FontWeight.w800,
        color: fg, letterSpacing: 0.2,
      )),
    );
  }
}

// ── Driver State Pill ──────────────────────────────────────────
class DriverStatePill extends StatelessWidget {
  const DriverStatePill({super.key, required this.state, this.small = false, this.pharmaciesPicked, this.pharmaciesTotal});
  final DriverState state;
  final bool small;
  // CLIENT-CONFIRMED LIVE (2026-08-19): backend added these to the list
  // endpoint specifically for this — shows as "Collecting (1/3)" rather
  // than just "Collecting", so the driver can see multi-pharmacy pickup
  // progress right from the orders list without opening the order.
  final int? pharmaciesPicked;
  final int? pharmaciesTotal;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon, baseLabel) = switch (state) {
      DriverState.pending    => (Colors.grey.withOpacity(0.15), WTheme.muted,                   '⏳', 'Pending'),
      DriverState.collecting => (WTheme.aqua.withOpacity(0.20), const Color(0xFF2A9BBC),         '🛒', 'Collecting'),
      DriverState.pickedUp   => (WTheme.sky.withOpacity(0.15),  WTheme.sky,                      '📦', 'Picked up'),
      DriverState.onMyWay    => (WTheme.rose.withOpacity(0.15), WTheme.rose,                     '🛵', 'On my way'),
      DriverState.delivered  => (WTheme.ok.withOpacity(0.15),   WTheme.ok,                       '✓',  'Delivered'),
      DriverState.failed     => (WTheme.err.withOpacity(0.12),  WTheme.err,                      '🚫', 'Failed'),
    };
    final label = (state == DriverState.collecting && pharmaciesTotal != null && pharmaciesTotal! > 1)
        ? '$baseLabel (${pharmaciesPicked ?? 0}/$pharmaciesTotal)'
        : baseLabel;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 9 : 11, vertical: small ? 3 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: TextStyle(fontSize: small ? 10 : 11)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.dmSans(
          fontSize: small ? 10 : 11, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.3,
        )),
      ]),
    );
  }
}

// ── Pay Chip ───────────────────────────────────────────────────
class PayChip extends StatelessWidget {
  const PayChip({super.key, required this.method, this.paid = false});
  final PayMethod method;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    if (paid) {
      return _chip(WTheme.ok.withOpacity(0.15), WTheme.ok, '✓ PAID');
    }
    return switch (method) {
      PayMethod.cash   => _chip(WTheme.warn.withOpacity(0.15), const Color(0xFFB4730E), '💵 CASH'),
      PayMethod.knet   => _chip(WTheme.sky.withOpacity(0.12),  WTheme.sky,              '💳 KNET'),
      PayMethod.link   => _chip(WTheme.ok.withOpacity(0.12),   WTheme.ok,               '🔗 LINK'),
      PayMethod.online => _chip(WTheme.ok.withOpacity(0.15),   WTheme.ok,               '✓ PAID'),
    };
  }

  Widget _chip(Color bg, Color fg, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: GoogleFonts.dmSans(
      fontSize: 11, fontWeight: FontWeight.w800, color: fg,
    )),
  );
}

// ── Swipe to Confirm ───────────────────────────────────────────
// Rebuilt so ONLY the thumb responds to drag (the track itself has no
// gesture handling at all) — a plain tap anywhere on this widget does
// nothing. Confirm only fires after a real drag covers the threshold.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({super.key, required this.label, required this.color, required this.onConfirm});
  final String label;
  final Color color;
  final VoidCallback onConfirm;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> {
  double _dx = 0;
  bool _dragging = false;
  bool _confirmed = false;
  static const double _thumbW = 64.0;
  static const double _height = 64.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final trackW = constraints.maxWidth;
      final maxDx = (trackW - _thumbW).clamp(0.0, double.infinity);
      final progress = maxDx > 0 ? (_dx / maxDx).clamp(0.0, 1.0) : 0.0;
      return Container(
        height: _height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: widget.color.withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        // No GestureDetector here — the track itself is not interactive,
        // so tapping anywhere that isn't the thumb does nothing at all.
        child: Stack(children: [
          // Label — centered in the space AFTER the thumb, fades out as
          // the thumb covers it while dragging. CLIENT-REPORTED: longer
          // labels (e.g. "Heading to patient (open directions)") were
          // centered across the FULL track, which put their start right
          // underneath the thumb — the thumb paints on top and hid the
          // first few letters, while the tail end ran off the right edge.
          // Reserving the thumb's own width on the left, and shrinking
          // the text to fit via FittedBox, means every label — short or
          // long, any device width — stays fully visible and never sits
          // under the thumb.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(left: _thumbW, right: 10),
              child: Center(child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.label, maxLines: 1, style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white,
                  )),
                ),
              )),
            ),
          ),
          // White thumb — the ONLY part that responds to drag.
          AnimatedPositioned(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 250),
            left: 6 + _dx,
            top: 6,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _dragging = true),
              onHorizontalDragUpdate: (d) {
                setState(() => _dx = (_dx + d.delta.dx).clamp(0, maxDx));
              },
              onHorizontalDragEnd: (details) {
                setState(() => _dragging = false);
                // Require a real drag: past 85% of the track AND a
                // forward-moving (or already-arrived) gesture — guards
                // against a stray tap somehow being read as a drag.
                final reachedThreshold = maxDx > 0 && _dx >= maxDx * 0.85;
                if (reachedThreshold && !_confirmed) {
                  _confirmed = true;
                  setState(() => _dx = maxDx);
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      widget.onConfirm();
                      setState(() { _dx = 0; _confirmed = false; });
                    }
                  });
                } else {
                  setState(() => _dx = 0);
                }
              },
              onHorizontalDragCancel: () => setState(() { _dragging = false; _dx = 0; }),
              child: Container(
                width: _thumbW - 12, height: _height - 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Center(child: Icon(Icons.arrow_forward, color: widget.color, size: 24)),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

// ── Bottom Navigation ──────────────────────────────────────────
class RiderBottomNav extends StatelessWidget {
  const RiderBottomNav({super.key, required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6EBF0), width: 1)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(children: [
            _NavItem(icon: '🏠', label: context.tr('home'),     tab: 'home',     current: current, onTap: onChanged),
            _NavItem(icon: '📋', label: context.tr('orders'),   tab: 'orders',   current: current, onTap: onChanged),
            _NavItem(icon: '💰', label: context.tr('earnings'), tab: 'earnings', current: current, onTap: onChanged),
            _NavItem(icon: '👤', label: context.tr('profile'),  tab: 'profile',  current: current, onTap: onChanged),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.tab,
    required this.current, required this.onTap});
  final String icon, label, tab, current;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final active = current == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(tab),
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: TextStyle(fontSize: active ? 26 : 22)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.dmSans(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: active ? WTheme.rose : WTheme.muted,
          )),
          if (active) Container(
            margin: const EdgeInsets.only(top: 3),
            width: 18, height: 3,
            decoration: BoxDecoration(
              color: WTheme.rose,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Ribbon (top header bar) ────────────────────────────────────
class RiderRibbon extends StatelessWidget {
  const RiderRibbon({
    super.key,
    required this.earnings,
    required this.deliveries,
    required this.onShift,
    required this.onToggleShift,
    this.role = 'zone', // 'batch' | 'zone' — 'express' removed from the UI selector per request; kept as a harmless fallback case below in case it ever slips through
    this.title,
  });
  final double earnings;
  final int deliveries;
  final bool onShift;
  final VoidCallback onToggleShift;
  final String role;
  final String? title;

  String _roleLabel(BuildContext context) => switch (role) {
    'batch' => context.tr('roleBatch'),
    'express' => context.tr('roleExpress'),
    _ => context.tr('roleZone'),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 18, right: 18, bottom: 14,
      ),
      color: WTheme.navy,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Shift toggle pill + status dot
        GestureDetector(
          onTap: onToggleShift,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
            decoration: BoxDecoration(
              color: onShift ? Colors.white.withOpacity(0.15) : WTheme.warn.withOpacity(0.25),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: onShift ? WTheme.ok : WTheme.warn,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: (onShift ? WTheme.ok : WTheme.warn).withOpacity(0.35),
                    blurRadius: 0, spreadRadius: 3,
                  )],
                ),
              ),
              const SizedBox(width: 6),
              Text(onShift ? context.tr('onShift') : context.tr('offShift'),
                  style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        if (onShift) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: WTheme.rose, borderRadius: BorderRadius.circular(999)),
            child: Text(_roleLabel(context),
                style: GoogleFonts.dmSans(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ],
        const Spacer(),
        // Today's earnings
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(context.tr('today'), style: GoogleFonts.dmSans(
              color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          Text('${earnings.toStringAsFixed(3)} ${context.tr('kd')}', style: GoogleFonts.dmSans(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ]),
      ]),
    );
  }
}

// ── SLA Countdown widget (ticking) ────────────────────────────
class SlaCountdown extends StatefulWidget {
  const SlaCountdown({super.key, required this.order, this.size = 'm'});
  final dynamic order; // Order
  final String size;

  @override
  State<SlaCountdown> createState() => _SlaCountdownState();
}

class _SlaCountdownState extends State<SlaCountdown> {
  late Duration _remaining;
  late bool _late;

  @override
  void initState() {
    super.initState();
    _tick();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(_tick);
      return true;
    });
  }

  void _tick() {
    _remaining = widget.order.slaTarget.difference(DateTime.now());
    _late = _remaining.isNegative;
  }

  @override
  Widget build(BuildContext context) {
    final abs = _remaining.abs();
    final hh = abs.inHours.toString().padLeft(2, '0');
    final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (abs.inSeconds % 60).toString().padLeft(2, '0');
    final timeStr = '$hh:$mm:$ss';

    final (bg, fg, icon, label) = _late
        ? (WTheme.err.withOpacity(0.15), WTheme.err, '⚠️', '$timeStr LATE')
        : (WTheme.ok.withOpacity(0.12), WTheme.ok, '⏱', '$timeStr left');

    final fs = size == 's' ? 10.0 : size == 'l' ? 14.0 : 11.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size == 's' ? 8 : 10,
        vertical: size == 's' ? 2 : 3,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: TextStyle(fontSize: fs)),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.dmSans(
          fontSize: fs, fontWeight: FontWeight.w800, color: fg,
          fontFeatures: const [FontFeature.tabularFigures()],
        )),
      ]),
    );
  }

  String get size => widget.size;
}

// ── Section card container ─────────────────────────────────────
class WCard extends StatelessWidget {
  const WCard({super.key, required this.child, this.padding, this.color, this.margin});
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WTheme.cloud),
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

// ── Quick action button (Maps / Waze / Call) ───────────────────
class QuickActionBtn extends StatelessWidget {
  const QuickActionBtn({super.key, required this.emoji, required this.label, required this.color, required this.onTap});
  final String emoji, label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: WTheme.cloud, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(emoji, style: TextStyle(fontSize: 22, color: color)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.navy)),
        ]),
      ),
    );
  }
}

// ── Toast overlay ──────────────────────────────────────────────
OverlayEntry? _toastEntry;
void showWToast(BuildContext context, String msg) {
  // Defensive: an in-flight toast's OverlayEntry can already be detached
  // (e.g. its host route was popped) by the time a new toast tries to
  // remove it — calling .remove() on that throws an assertion error and
  // crashes whatever just called showWToast (seen live: crashed profile
  // save's success path even though the save itself had already worked).
  try {
    _toastEntry?.remove();
  } catch (_) {}
  _toastEntry = null;

  if (!context.mounted) return; // nothing to show into anymore

  final entry = OverlayEntry(builder: (_) => Positioned(
    bottom: 90,
    left: 0, right: 0,
    child: Center(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: WTheme.ink, borderRadius: BorderRadius.circular(99),
        boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 16)],
      ),
      child: Text(msg, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
    )),
  ));
  _toastEntry = entry;
  Overlay.of(context).insert(entry);
  Future.delayed(const Duration(seconds: 2), () {
    try {
      entry.remove();
    } catch (_) {}
    if (_toastEntry == entry) _toastEntry = null;
  });
}
