import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';

// ── INCOMING BATCH OFFER SCREEN ─────────────────────────────────
// Matches the HTML prototype's BatchIncomingScreen (index.html) — this
// didn't exist anywhere in the app before: the backend endpoints
// (/batch-check, /batch/{id}/accept, /batch/{id}/reject) and the
// OrdersViewModel.pendingBatch data were already there, but nothing ever
// showed this offer to the driver or let them act on it. Orders in a
// pending batch just sat silently as OrderStatus.batchPending.
class BatchIncomingScreen extends StatefulWidget {
  const BatchIncomingScreen({super.key, required this.batch, required this.onAccept, required this.onReject});
  final Batch batch;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<BatchIncomingScreen> createState() => _BatchIncomingScreenState();
}

class _BatchIncomingScreenState extends State<BatchIncomingScreen> {
  static const int _totalSeconds = 15; // matches HTML's 15s offer window
  int _secondsLeft = _totalSeconds;
  Timer? _timer;
  bool _decided = false; // guards against double-fire (manual tap racing the auto-reject timeout)

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        _autoReject();
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _autoReject() {
    if (_decided) return;
    _decided = true;
    widget.onReject();
  }

  void _reject() {
    if (_decided) return;
    _decided = true;
    _timer?.cancel();
    widget.onReject();
  }

  void _accept() {
    if (_decided) return;
    _decided = true;
    _timer?.cancel();
    widget.onAccept();
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [WTheme.navy, Color(0xFF04527F), WTheme.rose],
          ),
        ),
        child: SafeArea(
          child: Stack(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: WTheme.rose,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: WTheme.rose.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Text('📦 BATCH OF ${batch.orders.length}',
                      style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 14),
                Text('New batch nearby',
                    style: GoogleFonts.dmSans(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('All from ${batch.pharmacyName}',
                    style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                const SizedBox(height: 20),
                // Countdown ring
                SizedBox(
                  width: 110, height: 110,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 110, height: 110,
                      child: CircularProgressIndicator(
                        value: _secondsLeft / _totalSeconds,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withOpacity(0.18),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    RichText(text: TextSpan(children: [
                      TextSpan(text: '$_secondsLeft',
                          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      TextSpan(text: ' sec',
                          style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _BatchTile(label: 'Stops', value: '${batch.orders.length}')),
                  const SizedBox(width: 6),
                  Expanded(child: _BatchTile(label: 'Distance', value: '${batch.totalDistance.toStringAsFixed(1)} km')),
                  const SizedBox(width: 6),
                  Expanded(child: _BatchTile(label: 'Earning', value: '${batch.totalEarning.toStringAsFixed(3)} KD')),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: WTheme.aqua, borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: Text('🏥', style: TextStyle(fontSize: 18))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SINGLE PICKUP',
                          style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      Text(batch.pharmacyName,
                          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: Text('DELIVER IN THIS ORDER',
                    style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
                const SizedBox(height: 6),
                ...batch.orders.map((o) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${o.stopNumber}',
                          style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 12))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.patient, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(o.addr1, style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.75), fontSize: 10)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${o.total.toStringAsFixed(3)} KD',
                          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: o.paid ? const Color(0xFF21B47A).withOpacity(0.25) : WTheme.sky.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(o.paid ? 'PAID' : o.payMethod.name.toUpperCase(),
                            style: GoogleFonts.dmSans(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ]),
                )),
              ]),
            ),
            // Bottom controls — ✕ reject + swipe-to-accept (reuses the
            // same SwipeToConfirm widget used elsewhere in the app)
            Positioned(
              bottom: 20, left: 18, right: 18,
              child: Row(children: [
                GestureDetector(
                  onTap: _reject,
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                    ),
                    child: const Center(child: Text('✕', style: TextStyle(color: Colors.white, fontSize: 22))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: SwipeToConfirm(label: 'Swipe to accept batch', color: WTheme.ok, onConfirm: _accept)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(value, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      ]),
    );
  }
}

// ── BATCH PICKUP SCREEN ────────────────────────────────────────
class BatchPickupScreen extends StatelessWidget {
  const BatchPickupScreen({
    super.key,
    required this.pharmacyName,
    required this.pharmacyAddr,
    required this.batchOrders,
    required this.pickedUp,
    required this.onPick,
    required this.onStart,
    required this.onBack,
    required this.onOpenOrder,
  });
  final String pharmacyName, pharmacyAddr;
  final List<Order> batchOrders;
  final Map<String, bool> pickedUp;
  final ValueChanged<String> onPick;
  final VoidCallback onStart, onBack;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final total = batchOrders.length;
    final picked = batchOrders.where((o) => pickedUp[o.id] == true).length;
    final allPicked = picked == total;

    return Scaffold(
      body: Column(children: [
        // Header
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 16, right: 16, bottom: 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [WTheme.aqua, WTheme.sky], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(context.tr('batchPickupTitle'), style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
            ]),
            const SizedBox(height: 12),
            Text('🏥 $pharmacyName', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(pharmacyAddr, style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : picked / total,
                minHeight: 7,
                backgroundColor: Colors.white.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            Text(context.tr('ordersCollectedTemplate').replaceFirst('{picked}', '$picked').replaceFirst('{total}', '$total'),
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: batchOrders.map((o) {
              final done = pickedUp[o.id] == true;
              return GestureDetector(
                onTap: () => onOpenOrder(o.id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: done ? WTheme.ok.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: done ? WTheme.ok : WTheme.cloud, width: done ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: done ? WTheme.ok : WTheme.navy,
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(done ? '✓' : '${o.stopNumber}',
                          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.patient, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 14, color: WTheme.navy)),
                      Text(context.tr('itemsCountKdTemplate').replaceFirst('{items}', '${o.items.length}').replaceFirst('{total}', o.total.toStringAsFixed(3)), style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted)),
                    ])),
                    if (!done)
                      GestureDetector(
                        onTap: () => onPick(o.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: WTheme.sky, borderRadius: BorderRadius.circular(10)),
                          child: Text(context.tr('pickBtn'), style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ),
                      )
                    else
                      Icon(Icons.check_circle, color: WTheme.ok),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: allPicked ? WTheme.ok : WTheme.muted,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: allPicked ? onStart : null,
              child: Text(allPicked ? context.tr('startDeliveries') : context.tr('collectAllFirst'), style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── MULTI-PHARMACY PICKUP SCREEN ───────────────────────────────
class MultiPickupScreen extends StatelessWidget {
  const MultiPickupScreen({
    super.key,
    required this.order,
    required this.onBack,
    required this.onOpenPharmacy,
    required this.onReadyToDeliver,
    required this.onOpenMapForPharmacy,
  });
  final Order order;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenPharmacy;
  final VoidCallback onReadyToDeliver;
  final ValueChanged<Pharmacy> onOpenMapForPharmacy;

  @override
  Widget build(BuildContext context) {
    // CLIENT-REPORTED (2026-08-19): rebuilt to match the original design
    // exactly (gradient progress card, segmented progress bar, SUGGESTED
    // badge on the next un-picked pharmacy, tappable address block,
    // pill-shaped OPEN PICKUP buttons) — the previous rebuild fixed the
    // broken data source but used much plainer, simplified styling.
    final pharmacies = order.pharmacies;
    final doneCount = pharmacies.where((p) => p.pickedUp).length;
    final allPicked = pharmacies.isNotEmpty && doneCount == pharmacies.length;
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Center(child: Text('‹', style: TextStyle(color: WTheme.navy, fontSize: 22, fontWeight: FontWeight.w700))),
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('multiPharmacyPickupTitle'), style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
                Text('#${order.id} · ${order.patient}', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
              ]),
            ]),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              // Progress card — gradient navy -> sky, segmented bar, count.
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [WTheme.navy, WTheme.sky]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.30), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('📦', style: TextStyle(fontSize: 26)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pick up from ${pharmacies.length} pharmacies',
                          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text("You can't deliver until every pickup is complete",
                          style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11)),
                    ])),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (int i = 0; i < pharmacies.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: pharmacies[i].pickedUp ? WTheme.ok : Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('$doneCount / ${pharmacies.length} picked up',
                        style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              // Driver chooses freely which pharmacy to go to first — no lock.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text('📍 CHOOSE ANY PHARMACY TO START WITH — PICK THE CLOSEST OR EASIEST',
                    style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.6)),
              ),
              const SizedBox(height: 8),
              for (int i = 0; i < pharmacies.length; i++) ...[
                Builder(builder: (context) {
                  final p = pharmacies[i];
                  final done = p.pickedUp;
                  // No lock — every non-done pharmacy is fully clickable.
                  // The "suggested" badge nudges toward the first
                  // un-picked entry but doesn't restrict the driver.
                  final suggested = !done && pharmacies.take(i).every((prev) => prev.pickedUp);
                  final key = '${p.sellerId ?? p.name}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: suggested
                          ? LinearGradient(colors: [WTheme.rose.withOpacity(0.05), Colors.white])
                          : null,
                      color: done ? WTheme.ok.withOpacity(0.06) : (suggested ? null : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: done ? WTheme.ok.withOpacity(0.3) : (suggested ? WTheme.rose : WTheme.cloud),
                        width: 1.5,
                      ),
                      boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: done ? WTheme.ok : (suggested ? WTheme.rose : WTheme.sky),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(child: Text(done ? '✓' : '${i + 1}',
                              style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text('PHARMACY ${i + 1}', style: GoogleFonts.dmSans(
                                fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                            if (done)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: WTheme.ok.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                                child: Text('PICKED UP', style: GoogleFonts.dmSans(fontSize: 9, color: WTheme.ok, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                              ),
                            if (suggested)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: WTheme.rose, borderRadius: BorderRadius.circular(999)),
                                child: Text('SUGGESTED', style: GoogleFonts.dmSans(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          Text(p.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16, letterSpacing: -0.2)),
                        ])),
                      ]),
                      const SizedBox(height: 10),
                      // Address — tappable, opens the map focused on this
                      // specific pharmacy (see onOpenMapForPharmacy).
                      GestureDetector(
                        onTap: () => onOpenMapForPharmacy(p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: WTheme.blush,
                            borderRadius: BorderRadius.circular(10),
                            border: Border(left: BorderSide(color: WTheme.aqua, width: 3)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('📍', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('ADDRESS', style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                              const SizedBox(height: 3),
                              Text((p.address?.isNotEmpty ?? false) ? p.address! : 'No address available',
                                  style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w800, color: WTheme.navy, letterSpacing: -0.2, height: 1.3)),
                            ])),
                            Text('TAP', style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                          ]),
                        ),
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('📦 ${p.itemsCount} item${p.itemsCount == 1 ? '' : 's'}',
                            style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontWeight: FontWeight.w600)),
                        if (!done)
                          GestureDetector(
                            onTap: () => onOpenPharmacy(key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: suggested ? WTheme.rose : WTheme.sky,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [BoxShadow(color: (suggested ? WTheme.rose : WTheme.sky).withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))],
                              ),
                              child: Text('OPEN PICKUP →', style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: WTheme.ok.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                            child: Text('✓ PICKED UP', style: GoogleFonts.dmSans(color: WTheme.ok, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                          ),
                      ]),
                    ]),
                  );
                }),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(12)),
                child: RichText(text: TextSpan(
                  style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.navy, height: 1.5),
                  children: [
                    const TextSpan(text: '📍 After all pickups\n', style: TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: "You'll head to ${order.patient} at ${order.addr1} · ${order.addr2}",
                        style: TextStyle(color: WTheme.muted)),
                  ],
                )),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, MediaQuery.of(context).padding.bottom + 22),
          child: allPicked
              ? SwipeToConfirm(label: context.tr('allPickedHeadToPatient'), color: WTheme.ok, onConfirm: onReadyToDeliver)
              : Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: Text(
                      '🔒 ${pharmacies.length - doneCount} more pickup${pharmacies.length - doneCount == 1 ? '' : 's'} before delivery',
                      style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13, fontWeight: FontWeight.w700))),
                ),
        ),
      ]),
    );
  }
}

// ── SINGLE PHARMACY STOP ───────────────────────────────────────
class SinglePharmacyStopScreen extends StatelessWidget {
  const SinglePharmacyStopScreen({
    super.key,
    required this.order,
    required this.sellerKey,
    required this.onBack,
    required this.onConfirmPickup,
  });
  final Order order;
  // '${sellerId ?? name}' — matches the key MultiPickupScreen builds for
  // each pharmacy, since seller ids aren't always present.
  final String sellerKey;
  final VoidCallback onBack;
  final VoidCallback onConfirmPickup;

  @override
  Widget build(BuildContext context) {
    final pharmacy = order.pharmacies.firstWhereOrNull((p) => '${p.sellerId ?? p.name}' == sellerKey);
    if (pharmacy == null) return const SizedBox.shrink();

    // CLIENT-REPORTED (2026-08-19): rebuilt to match the original design
    // — a richer hero header with order context and live countdown, real
    // item cards (price/qty, not just names), a subtotal, and a warning
    // banner — rather than the earlier, much plainer rebuild.
    final pickupIndex = order.pharmacies.indexOf(pharmacy) + 1;
    final totalPickups = order.pharmacies.length;
    // Cross-reference against order.items (which has real price/qty/tag)
    // by name, since pharmacy.itemNames only has plain strings — same
    // approach the design itself uses (looking up a catalog by name).
    final richItems = pharmacy.itemNames.map((name) {
      OrderItem? match;
      for (final it in order.items) { if (it.name == name) { match = it; break; } }
      return match ?? OrderItem(name: name, price: 0, qty: 1, tag: 'OTC');
    }).toList();
    final subtotal = richItems.fold<double>(0, (s, it) => s + it.price * it.qty);

    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(22, MediaQuery.of(context).padding.top + 14, 22, 20),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [WTheme.aqua, WTheme.sky])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text('‹', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700))),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: WTheme.navy, borderRadius: BorderRadius.circular(999)),
                child: Text('PHARMACY $pickupIndex OF $totalPickups', style: GoogleFonts.dmSans(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ),
            ]),
            const SizedBox(height: 14),
            Text('PICKUP AT', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(pharmacy.name, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.3)),
            const SizedBox(height: 8),
            RichText(text: TextSpan(
              style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w600),
              children: [
                const TextSpan(text: '🧾 Part of order '),
                TextSpan(text: '#${order.id}', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' · for ${order.patient}'),
              ],
            )),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(999)),
                child: Text('🏥 PICKING UP', style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ),
              if (pharmacy.address != null && pharmacy.address!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(999)),
                  child: Text('📍 ${pharmacy.address}', style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ),
            ]),
            if (order.status != OrderStatus.done && order.status != OrderStatus.failed) ...[
              const SizedBox(height: 8),
              SlaCountdown(order: order, size: 'l'),
            ],
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Items to pick up (${richItems.length})', style: GoogleFonts.dmSans(
                        fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF2A9BBC).withOpacity(0.18), borderRadius: BorderRadius.circular(999)),
                      child: Text('🏥 ${pharmacy.name}', style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF2A9BBC))),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ...richItems.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // CLIENT-REPORTED (2026-08-22): a real, valid image
                      // URL was confirmed in the raw response, but the
                      // thumbnail showed completely blank — no image, no
                      // fallback emoji either. Root cause: BoxDecoration's
                      // DecorationImage has no loading or error state at
                      // all — while an image is still fetching, or if it
                      // ever fails to load, it just silently shows
                      // nothing, revealing the plain background color.
                      // Image.network (used directly here instead)
                      // supports both loadingBuilder and errorBuilder,
                      // so a fallback is always visible instead of a
                      // blank box during that window.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 52, height: 52,
                          color: WTheme.blush,
                          child: item.imageUrl != null
                              ? Image.network(
                                  item.imageUrl!,
                                  width: 52, height: 52,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) =>
                                      progress == null ? child : const Center(child: SizedBox(
                                          width: 18, height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2))),
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(child: Text('💊', style: TextStyle(fontSize: 20))),
                                )
                              : const Center(child: Text('💊', style: TextStyle(fontSize: 20))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 13, height: 1.3)),
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          RichText(text: TextSpan(children: [
                            TextSpan(text: item.price.toStringAsFixed(3), style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.rose, fontSize: 14)),
                            TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w600)),
                          ])),
                          Text('×${item.qty}', style: GoogleFonts.dmSans(color: WTheme.navy, fontSize: 13, fontWeight: FontWeight.w800)),
                        ]),
                      ])),
                    ]),
                  )),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: WTheme.cloud, width: 1))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic, children: [
                      Text('PHARMACY SUB-TOTAL', style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: subtotal.toStringAsFixed(3), style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 16)),
                        TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontWeight: FontWeight.w600)),
                      ])),
                    ]),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: WTheme.warn.withOpacity(0.10),
                  border: Border(left: BorderSide(color: WTheme.warn, width: 3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('⚠️ Verify every item from this pharmacy before confirming pickup. You\'ll move to the next pharmacy after.',
                    style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFFB4730E), height: 1.5)),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 22),
          child: SwipeToConfirm(
            label: 'Confirm pickup at ${pharmacy.name}',
            color: WTheme.ok,
            onConfirm: onConfirmPickup,
          ),
        ),
      ]),
    );
  }
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}
