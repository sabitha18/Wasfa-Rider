import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/data/repositories/order_repository.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    required this.onBack,
    required this.onArrive,
    required this.onCantDeliver,
    required this.onTransitionState,
    required this.onMultiPickup,
    required this.onOpenMap,
  });
  final String orderId;
  final VoidCallback onBack, onArrive, onCantDeliver, onMultiPickup;
  final void Function(String id, DriverState state) onTransitionState;
  final ValueChanged<Order> onOpenMap;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Was previously never called at all — this screen only ever showed
    // whatever the last /orders or /batch list poll happened to have
    // cached, with no way to see a request for it in logcat since none
    // was ever made. Now re-checks the backend fresh every time this
    // screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrdersViewModel>().refreshOrder(widget.orderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    final onBack = widget.onBack;
    final onArrive = widget.onArrive;
    final onCantDeliver = widget.onCantDeliver;
    final onTransitionState = widget.onTransitionState;
    final onMultiPickup = widget.onMultiPickup;
    final onOpenMap = widget.onOpenMap;
    final vm    = context.watch<OrdersViewModel>();
    final order = vm.findById(orderId);
    if (order == null) {
      // TEMP trace — tracing an intermittent "Order not found" report.
      // Shows exactly which ID was requested vs what's actually loaded,
      // so we can tell whether this is an ID-format mismatch, a genuine
      // race with the order list refreshing this order out from under the
      // screen, or something else entirely. Remove once confirmed/fixed.
      debugPrint('[OrderDetail] "$orderId" not found. Currently loaded IDs: ${vm.orders.map((o) => o.id).toList()}');
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: WTheme.navy), onPressed: onBack),
        ),
        body: Center(child: Text(context.tr('orderNotFound'))),
      );
    }
    final allCount = vm.orders.where((o) => [
      OrderStatus.active, OrderStatus.next, OrderStatus.later, OrderStatus.batchPending
    ].contains(o.status)).length;

    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        // ── Blue gradient hero ────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF023B60), Color(0xFF1E9CD7)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Row 1: back + STOP X OF Y + countdown
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Center(child: Text('‹', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700))),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: WTheme.aqua, borderRadius: BorderRadius.circular(999)),
                    child: Text('STOP ${order.stopNumber} OF $allCount',
                        style: GoogleFonts.dmSans(color: WTheme.navy, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                  ),
                  if (order.status != OrderStatus.done && order.status != OrderStatus.failed)
                    SlaCountdown(order: order, size: 'm')
                  else
                    const SizedBox(width: 34),
                ]),
                const SizedBox(height: 10),
                // Row 2: order ID + total
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('#${order.id}', style: GoogleFonts.dmSans(
                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: order.total.toStringAsFixed(3),
                            style: GoogleFonts.dmSans(color: Colors.white, fontSize: 22,
                                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(
                            color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                      ])),
                    ]),
                const SizedBox(height: 4),
                // Date
                Text('📅 ${_fmtDateLong(order.createdAt)}',
                    style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                // Status pills row
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _HeroPill(text: '${_driverIcon(order.driverState)} ${_driverLabel(context, order.driverState)}'),
                  _HeroPill(
                    text: order.paid ? '✓ PAID' : '${order.payMethod.name.toUpperCase()} · NOT PAID',
                    color: order.paid ? WTheme.ok.withOpacity(0.30) : WTheme.warn.withOpacity(0.30),
                  ),
                  _HeroPill(text: '📍 ${order.distanceKm} km · ⏱ ${order.etaMin} min'),
                  _HeroPill(text: '📦 ${order.items.length} item${order.items.length != 1 ? "s" : ""}'),
                ]),
              ]),
            ),
          ),
        ),
        // ── Scrollable body ───────────────────────────────────
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(children: [
            // Customer note
            if (order.customerNote != null) _NoteCard(note: order.customerNote!),
            // Items card
            _ItemsCard(order: order),
            // Customer details card
            _CustomerCard(order: order, onOpenMap: onOpenMap),
            // Building photos block (before total — matches HTML)
            _BuildingPhotosBlock(order: order),
            // Total to collect card
            _TotalCard(order: order),
            // Send payment link / already paid
            if (!order.paid)
              _whatsappBtn(order, context)
            else
              _paidBanner(),
            // Big payment status block (bottom of scroll)
            _BigPaymentStatus(order: order),
            const SizedBox(height: 14),
          ]),
        )),
        // ── Bottom action bar ─────────────────────────────────
        Container(
          color: WTheme.blush,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(children: [
            _DriverActionBar(
              order: order,
              onTransitionState: onTransitionState,
              onArrive: onArrive,
              onMultiPickup: onMultiPickup,
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onCantDeliver,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: WTheme.err, width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text("🚫 Can't deliver — failed",
                    style: GoogleFonts.dmSans(color: WTheme.err, fontSize: 13, fontWeight: FontWeight.w700))),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _whatsappBtn(Order order, BuildContext context) => GestureDetector(
    onTap: () async {
      // TEMPORARILY DISABLED — this used to build a WhatsApp message
      // containing a fabricated payment URL (pay.wasfakw.com/o/{id}) that
      // was never confirmed with backend and almost certainly isn't a
      // real, working page. Sending a broken payment link to an actual
      // customer is worse than not sending one at all. Restore the real
      // link/flow here once backend confirms the actual format or endpoint.
      showWToast(context, "Payment link isn't ready yet — check back soon");
    },
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
        boxShadow: [BoxShadow(color: const Color(0xFF25D366).withOpacity(0.4), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Center(child: Text('🔗 Send payment link to patient via WhatsApp',
          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800))),
    ),
  );

  Widget _paidBanner() => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: WTheme.ok.withOpacity(0.10),
      border: Border.all(color: WTheme.ok, width: 1.5, style: BorderStyle.solid),
    ),
    child: Center(child: Text('✓ This order is already paid — no collection needed',
        style: GoogleFonts.dmSans(color: WTheme.ok, fontSize: 13, fontWeight: FontWeight.w700))),
  );

  static String _fmtDateLong(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${months[d.month-1]} ${d.day}, $h:${d.minute.toString().padLeft(2,'0')} $ampm';
  }

  static String _driverLabel(BuildContext context, DriverState s) => switch (s) {
    DriverState.pending    => context.tr('driverPending'),
    DriverState.collecting => context.tr('driverCollecting'),
    DriverState.pickedUp   => context.tr('driverPickedUp'),
    DriverState.onMyWay    => context.tr('driverOnMyWay'),
    DriverState.delivered  => context.tr('driverDelivered'),
    DriverState.failed     => context.tr('driverFailed'),
  };

  static String _driverIcon(DriverState s) => switch (s) {
    DriverState.pending    => '⏳',
    DriverState.collecting => '🛒',
    DriverState.pickedUp   => '📦',
    DriverState.onMyWay    => '🛵',
    DriverState.delivered  => '✓',
    DriverState.failed     => '🚫',
  };
}

// ── Hero pill ──────────────────────────────────────────────────
class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color ?? Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: GoogleFonts.dmSans(
        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
  );
}

// ── Customer note ──────────────────────────────────────────────
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [WTheme.warn.withOpacity(0.13), WTheme.warn.withOpacity(0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      border: Border.all(color: WTheme.warn, width: 2),
      boxShadow: [BoxShadow(color: WTheme.warn.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))],
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: WTheme.warn, borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Text('📝', style: TextStyle(fontSize: 20))),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('⚠ CUSTOMER NOTE — PLEASE READ', style: GoogleFonts.dmSans(
            fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF8A5A0A), letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(note, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700, color: WTheme.ink, height: 1.4)),
      ])),
    ]),
  );
}

// ── Items card ─────────────────────────────────────────────────
class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('📦 ITEMS (${order.items.length})', style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
        if (order.multiPharmacy)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: WTheme.aqua.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999)),
            child: Text('🏥 ${order.pickups.length} pharmacies',
                style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800,
                    color: const Color(0xFF2A9BBC))),
          ),
      ]),
      const SizedBox(height: 12),
      ...order.items.map((item) => _RichItemCard(item: item, showPharmacy: order.multiPharmacy)),
    ]),
  );
}

// ── Rich item card (matches HTML's RichItemCard) ───────────────
class _RichItemCard extends StatefulWidget {
  const _RichItemCard({required this.item, this.showPharmacy = false});
  final OrderItem item;
  final bool showPharmacy;

  @override
  State<_RichItemCard> createState() => _RichItemCardState();
}

class _RichItemCardState extends State<_RichItemCard> {
  void _showLightbox() {
    final item = widget.item;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            // ×  close button — top right, matches HTML
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 20,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                  ),
                  child: const Center(child: Text('×', style: TextStyle(
                      color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
                ),
              ),
            ),
            // Content — centred, zoom animation via scale
            Center(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
              child: GestureDetector(
                onTap: () {}, // prevent tap-through
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Big image box — square aspect ratio matches HTML
                  Container(
                    width: double.infinity,
                    height: 280,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [item.color, item.color.withOpacity(0.55)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: item.color.withOpacity(0.67), blurRadius: 80, offset: const Offset(0, 30)),
                        BoxShadow(color: Colors.white.withOpacity(0.12), blurRadius: 0, spreadRadius: 1),
                      ],
                    ),
                    child: Stack(children: [
                      if (item.imageUrl != null)
                        Positioned.fill(child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.network(item.imageUrl!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Text('💊', style: TextStyle(fontSize: 120, height: 1)))),
                        ))
                      else
                        const Center(child: Text('💊', style: TextStyle(fontSize: 120, height: 1))),
                      Positioned(top: 14, right: 14, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: WTheme.rose,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [BoxShadow(color: WTheme.rose.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))],
                        ),
                        child: Text(item.tag, style: GoogleFonts.dmSans(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  // Info card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 50, offset: Offset(0, 20))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800,
                          color: WTheme.navy, fontSize: 17, letterSpacing: -0.2, height: 1.3)),
                      const SizedBox(height: 12),
                      Container(height: 1, color: WTheme.cloud),
                      const SizedBox(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        RichText(text: TextSpan(children: [
                          TextSpan(text: item.price.toStringAsFixed(3),
                              style: GoogleFonts.dmSans(fontWeight: FontWeight.w800,
                                  color: WTheme.rose, fontSize: 22, letterSpacing: -0.4)),
                          TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(
                              fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w700)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                                colors: [Color(0xFF023B60), Color(0xFF04527F)]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.4),
                                blurRadius: 14, offset: const Offset(0, 6))],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic, children: [
                                Text('QTY', style: GoogleFonts.dmSans(
                                    color: Colors.white.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                                const SizedBox(width: 6),
                                Text('×${item.qty}', style: GoogleFonts.dmSans(
                                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                              ]),
                        ),
                      ]),
                      if (item.pharmacy != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: WTheme.blush,
                            borderRadius: BorderRadius.circular(10),
                            border: Border(left: BorderSide(color: WTheme.aqua, width: 3)),
                          ),
                          child: RichText(text: TextSpan(
                            style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontWeight: FontWeight.w700),
                            children: [
                              const TextSpan(text: '🏥 From: '),
                              TextSpan(text: item.pharmacy!, style: TextStyle(
                                  color: WTheme.navy, fontWeight: FontWeight.w800)),
                            ],
                          )),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WTheme.cloud, width: 1.5)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Color image box — tap to open lightbox
        GestureDetector(
          onTap: _showLightbox,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, right: 4), // room for badge overflow
            child: SizedBox(
              width: 64, height: 64,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [item.color, item.color.withOpacity(0.55)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: item.color.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: item.imageUrl != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(item.imageUrl!, fit: BoxFit.cover, width: 64, height: 64,
                        errorBuilder: (_, __, ___) => const Center(child: Text('💊', style: TextStyle(fontSize: 28)))),
                  )
                      : const Center(child: Text('💊', style: TextStyle(fontSize: 28))),
                ),
                // Tag badge
                Positioned(top: -4, right: -4, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: WTheme.rose, borderRadius: BorderRadius.circular(6),
                      boxShadow: [BoxShadow(color: WTheme.rose.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2))]),
                  child: Text(item.tag, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                )),
                // Zoom affordance
                Positioned(bottom: 3, right: 3, child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
                  child: const Center(child: Text('⤢', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                )),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 13, height: 1.3)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RichText(text: TextSpan(children: [
              TextSpan(text: item.price.toStringAsFixed(3), style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.rose, fontSize: 15)),
              TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w600)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF023B60), Color(0xFF04527F)]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.33), blurRadius: 10, offset: const Offset(0, 4))]),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic, children: [
                    Text('QTY', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Text('×${item.qty}', style: GoogleFonts.dmSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  ]),
            ),
          ]),
          if (widget.showPharmacy && item.pharmacy != null) ...[
            const SizedBox(height: 4),
            Text('🏥 Seller: ${item.pharmacy}', style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w600)),
          ],
        ])),
      ]),
    );
  }
}

// ── Customer details card ──────────────────────────────────────
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.order, required this.onOpenMap});
  final Order order;
  final ValueChanged<Order> onOpenMap;

  @override
  Widget build(BuildContext context) {
    final initials = order.patient.split(' ').map((n) => n.isNotEmpty ? n[0] : '').take(2).join();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('👤 CUSTOMER DETAILS', style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        // Patient row
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: WTheme.blush, borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(initials, style: GoogleFonts.dmSans(
                color: WTheme.rose, fontWeight: FontWeight.w800, fontSize: 16))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.patient, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 15)),
            Text('${order.phone} · masked', style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted)),
          ])),
        ]),
        const SizedBox(height: 12),
        // Address block
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(0)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📍', style: TextStyle(color: WTheme.rose, fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.addr1, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 13, height: 1.4)),
              Text(order.addr2, style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted)),
              if (order.landmark != null)
                Text('Landmark: ${order.landmark}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontStyle: FontStyle.italic)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        // 2×2 action grid
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 4.5,
          children: [
            _ContactBtn(label: '📞 ${context.tr('call')}', bg: WTheme.ok, fg: Colors.white,
                onTap: () => _launch('tel:${order.phone.replaceAll(RegExp(r'\s'), '')}')),
            _ContactBtn(label: context.tr('whatsapp'), bg: const Color(0xFF25D366), fg: Colors.white,
                onTap: () => _launch('https://wa.me/${order.phone.replaceAll(RegExp(r'\D'), '')}')),
            _ContactBtn(label: '🗺 ${context.tr('map')}', outline: const Color(0xFF4285F4), fg: const Color(0xFF4285F4),
                onTap: () => onOpenMap(order)),
            _ContactBtn(label: '🚗 ${context.tr('waze')}', outline: const Color(0xFF33CCFF), fg: const Color(0xFF33CCFF),
                onTap: () => _launch('https://waze.com/ul?q=${Uri.encodeComponent('${order.addr1}, Kuwait')}')),
          ],
        ),
        const SizedBox(height: 12),
        // Ask dispatcher
        GestureDetector(
          onTap: () => showWToast(context, '🆘 Dispatcher notified to call patient'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: WTheme.cloud, width: 1, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(child: Text('🆘 Need help reaching them? Ask dispatcher to call →',
                style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 12, fontWeight: FontWeight.w700))),
          ),
        ),
      ]),
    );
  }

  void _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }
}

class _ContactBtn extends StatelessWidget {
  const _ContactBtn({required this.label, this.bg, this.outline, required this.fg, required this.onTap});
  final String label;
  final Color? bg, outline, fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        border: outline != null ? Border.all(color: outline!, width: 1.5) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: Text(label, style: GoogleFonts.dmSans(
          color: fg, fontWeight: FontWeight.w700, fontSize: 12))),
    ),
  );
}

// ── Total to collect card ──────────────────────────────────────
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final delivery = order.deliveryFee ?? 1.500;
    final discount = order.discount ?? 0.0;
    final subtotal = order.total - delivery + discount;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(context.tr('totalToCollect'), style: GoogleFonts.dmSans(
              fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
          PayChip(method: order.payMethod, paid: order.paid),
        ]),
        const SizedBox(height: 14),
        _TotalRow(context.tr('subtotal'), subtotal),
        if (discount > 0)
          _TotalRow(context.tr('discount'), -discount, color: WTheme.ok)
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(context.tr('discountCap'), style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              Text(context.tr('noDiscount'), style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
        _TotalRow(context.tr('deliveryFee'), delivery),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: order.paid ? null
                : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF023B60), Color(0xFF04527F)]),
            color: order.paid ? WTheme.ok.withOpacity(0.10) : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(context.tr('total'), style: GoogleFonts.dmSans(
                    color: order.paid ? WTheme.ok : Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                RichText(text: TextSpan(children: [
                  TextSpan(text: order.total.toStringAsFixed(3),
                      style: GoogleFonts.dmSans(color: order.paid ? WTheme.ok : Colors.white,
                          fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(
                      color: (order.paid ? WTheme.ok : Colors.white).withOpacity(0.7),
                      fontSize: 13, fontWeight: FontWeight.w600)),
                ])),
              ]),
        ),
      ]),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.amount, {this.color});
  final String label;
  final double amount;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label.toUpperCase(), style: GoogleFonts.dmSans(
          fontSize: 12, color: color ?? WTheme.muted,
          fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      Text('${amount < 0 ? "− " : ""}${amount.abs().toStringAsFixed(3)} ${context.tr('kd')}',
          style: GoogleFonts.dmSans(color: color ?? WTheme.navy,
              fontSize: 14, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ── Big Payment Status ─────────────────────────────────────────
class _BigPaymentStatus extends StatelessWidget {
  const _BigPaymentStatus({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final isPaid = order.paid;
    final method = order.payMethod;
    final String label, sub, methodLabel, icon;
    final List<Color> gradColors;

    if (isPaid) {
      label = context.tr('alreadyPaidLabel'); sub = context.tr('noCollectionNeeded');
      methodLabel = context.tr('paidCap'); icon = '✓';
      gradColors = [WTheme.ok, const Color(0xFF1A9C68)];
    } else if (method == PayMethod.knet) {
      label = context.tr('collectByKnet'); sub = context.tr('useCardTerminal');
      methodLabel = context.tr('knetCard'); icon = '💳';
      gradColors = [WTheme.sky, const Color(0xFF1577AC)];
    } else if (method == PayMethod.link) {
      label = context.tr('paymentLinkSent'); sub = context.tr('confirmPatientPaid');
      methodLabel = context.tr('linkCap'); icon = '🔗';
      gradColors = [WTheme.ok, const Color(0xFF1A9C68)];
    } else {
      label = context.tr('collectCash'); sub = context.tr('exactChangePreferred');
      methodLabel = context.tr('cashOnDelivery'); icon = '💵';
      gradColors = [WTheme.warn, const Color(0xFFC7800E)];
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: gradColors),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 32, offset: Offset(0, 14))],
      ),
      child: Stack(children: [
        Positioned(top: -10, right: -10,
            child: Text(icon, style: const TextStyle(fontSize: 90, color: Colors.white10))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('paymentStatus'), style: GoogleFonts.dmSans(
              color: Colors.white.withOpacity(0.85), fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.dmSans(
              color: Colors.white, fontSize: 24,
              fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15)),
          const SizedBox(height: 6),
          Text(sub, style: GoogleFonts.dmSans(
              color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(
                color: Colors.white.withOpacity(0.35), width: 1.5, style: BorderStyle.solid))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(methodLabel, style: GoogleFonts.dmSans(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: order.total.toStringAsFixed(3), style: GoogleFonts.dmSans(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(
                        color: Colors.white.withOpacity(0.75), fontSize: 12, fontWeight: FontWeight.w700)),
                  ])),
                ]),
          ),
        ]),
      ]),
    );
  }
}

// ── Building Photos Block ──────────────────────────────────────
// Was entirely local/in-memory before — the list reset every time you
// left this screen, "ADD BUILDING PHOTO" never opened a real camera, and
// nothing was ever sent to the backend. The endpoints for this
// (GET/POST /orders/{co}/building-photos) were already built and CONFIRMED
// working — just never actually called from here.
class _BuildingPhotosBlock extends StatefulWidget {
  const _BuildingPhotosBlock({required this.order});
  final Order order;
  @override
  State<_BuildingPhotosBlock> createState() => _BuildingPhotosBlockState();
}

class _BuildingPhotosBlockState extends State<_BuildingPhotosBlock> {
  final _repo = OrderRepository();
  final _noteCtrl = TextEditingController();
  List<BuildingPhoto> _photos = [];
  bool _loading = true;
  bool _capturing = false;
  bool _uploading = false;
  File? _pickedFile;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await _repo.fetchBuildingPhotos(widget.order.co ?? widget.order.id);
      if (!mounted) return;
      setState(() { _photos = photos; _loading = false; });
    } catch (e) {
      debugPrint('[BuildingPhotos] fetch failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    setState(() => _capturing = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) { setState(() => _capturing = false); return; } // driver backed out of the camera
      setState(() => _pickedFile = File(file.path));
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _submit() async {
    final file = _pickedFile;
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      // customer_id is OPTIONAL and meant to scope a photo to a specific
      // customer (so it resurfaces on THEIR future orders, not just this
      // one). order.id would be wrong here — it identifies this single
      // delivery, not the customer, and changes every order. There's no
      // real customer identifier anywhere in the order data the app
      // receives (only a name + phone), so this is left unset rather than
      // sending a misleading value under that field name. If backend wants
      // real per-customer tracking to work, order.phone is the most
      // stable customer-identity proxy available — worth asking them.
      await _repo.uploadBuildingPhoto(widget.order.co ?? widget.order.id, file.path);
      if (!mounted) return;
      setState(() { _capturing = false; _pickedFile = null; _uploading = false; });
      _noteCtrl.clear();
      await _loadPhotos(); // refresh with the real uploaded photo from the server
      if (mounted) showWToast(context, '📷 Photo shared with other drivers');
    } catch (e) {
      debugPrint('[BuildingPhotos] upload failed: $e');
      if (!mounted) return;
      setState(() => _uploading = false);
      showWToast(context, "Couldn't upload the photo — please try again");
    }
  }

  void _cancel() {
    setState(() { _capturing = false; _pickedFile = null; });
    _noteCtrl.clear();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white,
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(context.tr('buildingPhotosHeader'), style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
        if (_photos.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: WTheme.ok.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
            child: Text('${_photos.length} ${context.tr('onFile')}', style: GoogleFonts.dmSans(
                color: WTheme.ok, fontSize: 9, fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
      const SizedBox(height: 10),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
        )
      else if (_photos.isNotEmpty)
        SizedBox(height: 130, child: ListView.separated(
          scrollDirection: Axis.horizontal, itemCount: _photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final photo = _photos[i];
            return Container(
              width: 100, padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: WTheme.blush, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WTheme.cloud, width: 1.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(photo.url, height: 90, width: 90, fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null ? child : Container(
                          height: 90, width: 90, color: WTheme.cloud,
                          child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
                      errorBuilder: (_, __, ___) => Container(
                          height: 90, width: 90, color: WTheme.cloud,
                          child: const Center(child: Text('📷', style: TextStyle(fontSize: 26))))),
                ),
                if (photo.by != null) ...[
                  const SizedBox(height: 3),
                  Text('${context.tr('byPrefix')} ${photo.by}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w700, color: WTheme.navy)),
                ],
                if (photo.note != null && photo.note!.trim().isNotEmpty)
                  Text(photo.note!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 9, color: WTheme.muted)),
              ]),
            );
          },
        ))
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WTheme.blush, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WTheme.cloud)),
          child: Center(child: Text(
              context.tr('noPhotosYet'),
              style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center)),
        ),
      const SizedBox(height: 12),
      if (_capturing)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WTheme.blush, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WTheme.aqua, width: 1.5)),
          child: Column(children: [
            if (_pickedFile != null)
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.file(_pickedFile!, height: 140, width: double.infinity, fit: BoxFit.cover))
            else
              Container(height: 140, width: double.infinity,
                  decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)))),
            const SizedBox(height: 10),
            TextField(controller: _noteCtrl,
                style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.navy),
                decoration: InputDecoration(
                  hintText: context.tr('addQuickNoteHint'),
                  hintStyle: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.cloud)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.cloud, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                )),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: GestureDetector(onTap: _uploading ? null : _cancel,
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text(context.tr('cancel'), style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 12)))))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: GestureDetector(onTap: (_pickedFile != null && !_uploading) ? _submit : null,
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          color: (_pickedFile != null) ? WTheme.ok : WTheme.cloud,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: (_pickedFile != null) ? [BoxShadow(color: WTheme.ok.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))] : null),
                      child: Center(child: _uploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(context.tr('saveAndShare'), style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)))))),
            ]),
          ]),
        )
      else
        GestureDetector(onTap: _pickPhoto,
            child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WTheme.aqua, width: 1.5, style: BorderStyle.solid)),
                child: Center(child: Text('📷 ADD BUILDING PHOTO', style: GoogleFonts.dmSans(
                    color: WTheme.sky, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4))))),
    ]),
  );
}

// ── Driver action bar (bottom swipe section) ──────────────────
class _DriverActionBar extends StatefulWidget {
  const _DriverActionBar({
    required this.order,
    required this.onTransitionState,
    required this.onArrive,
    required this.onMultiPickup,
  });
  final Order order;
  final void Function(String id, DriverState state) onTransitionState;
  final VoidCallback onArrive, onMultiPickup;

  @override
  State<_DriverActionBar> createState() => _DriverActionBarState();
}

class _DriverActionBarState extends State<_DriverActionBar> {
  void _transition(DriverState state) {
    widget.onTransitionState(widget.order.id, state);
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.order.driverState;

    // Done/failed — show status banner
    if (ds == DriverState.delivered || ds == DriverState.failed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (ds == DriverState.failed ? WTheme.err : WTheme.ok).withOpacity(0.10),
          border: Border.all(
              color: ds == DriverState.failed ? WTheme.err : WTheme.ok,
              width: 1.5, style: BorderStyle.solid),
        ),
        child: Center(child: Text(
          ds == DriverState.failed ? context.tr('deliveryFailedMsg') : context.tr('deliveredComplete'),
          style: GoogleFonts.dmSans(
              color: ds == DriverState.failed ? WTheme.err : WTheme.ok,
              fontSize: 13, fontWeight: FontWeight.w700),
        )),
      );
    }

    final String stepLabel, swipeLabel;
    final Color swipeColor, labelColor;
    final VoidCallback onConfirm;

    switch (ds) {
      case DriverState.pending:
        stepLabel  = context.tr('step1Heading');
        swipeLabel = widget.order.multiPharmacy
            ? context.tr('headingToFirstPharmacy')
            : context.tr('headingToPharmacy');
        swipeColor = WTheme.sky;
        labelColor = const Color(0xFF2A9BBC);
        onConfirm  = () { _transition(DriverState.collecting); };
      case DriverState.collecting:
        stepLabel  = context.tr('step2Collecting');
        swipeLabel = widget.order.multiPharmacy
            ? context.tr('openPickupChecklist')
            : context.tr('confirmPickedUp');
        swipeColor = WTheme.aqua;
        labelColor = WTheme.aqua;
        onConfirm  = widget.order.multiPharmacy
            ? () => Future.microtask(widget.onMultiPickup)
            : () { _transition(DriverState.pickedUp); };
      case DriverState.pickedUp:
        stepLabel  = context.tr('step3ItemsInHand');
        swipeLabel = context.tr('headingToPatient');
        swipeColor = WTheme.rose;
        labelColor = WTheme.rose;
        onConfirm  = () { _transition(DriverState.onMyWay); };
      default: // onMyWay
        stepLabel  = context.tr('step4OnTheWay');
        swipeLabel = context.tr('arrivedAtPatient');
        swipeColor = WTheme.aqua;
        labelColor = WTheme.aqua;
        onConfirm  = () => Future.microtask(widget.onArrive);
    }

    return Column(children: [
      Text(stepLabel.toUpperCase(), textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800,
              color: labelColor, letterSpacing: 0.6)),
      const SizedBox(height: 8),
      SwipeToConfirm(label: swipeLabel, color: swipeColor, onConfirm: onConfirm),
    ]);
  }
}
