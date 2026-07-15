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
  });
  final Order order;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenPharmacy;
  final VoidCallback onReadyToDeliver;

  @override
  Widget build(BuildContext context) {
    final allPicked = order.pickups.every((p) => p.picked);
    return Scaffold(
      body: Column(children: [
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 16, right: 16, bottom: 14),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [WTheme.navy, Color(0xFF04527F)])),
          child: Row(children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('multiPharmacyPickupTitle'), style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              Text(order.patient, style: GoogleFonts.dmSans(color: Colors.white60, fontSize: 12)),
            ])),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WCard(child: Text(context.tr('collectAllPharmaciesIntro').replaceFirst('{n}', '${order.pickups.length}'),
                  style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.muted))),
              ...order.pickups.asMap().entries.map((e) {
                final idx = e.key;
                final p = e.value;
                return GestureDetector(
                  onTap: () => onOpenPharmacy(p.phId),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: p.picked ? WTheme.ok.withOpacity(0.06) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.picked ? WTheme.ok : WTheme.cloud, width: p.picked ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: p.picked ? WTheme.ok : WTheme.aqua, shape: BoxShape.circle),
                        child: Center(child: Text(p.picked ? '✓' : '${idx + 1}',
                            style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 14, color: WTheme.navy)),
                        Text(p.addr, style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted)),
                        Text(context.tr('itemsCountTemplate').replaceFirst('{n}', '${p.items.length}'), style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.sky, fontWeight: FontWeight.w600)),
                      ])),
                      Icon(p.picked ? Icons.check_circle : Icons.chevron_right, color: p.picked ? WTheme.ok : WTheme.muted),
                    ]),
                  ),
                );
              }),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: allPicked ? WTheme.rose : WTheme.muted,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: allPicked ? onReadyToDeliver : null,
              child: Text(allPicked ? context.tr('allPickedHeadToPatient') : context.tr('collectFromAllFirst'),
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
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
    required this.phId,
    required this.onBack,
    required this.onConfirmPickup,
  });
  final Order order;
  final String phId;
  final VoidCallback onBack;
  final VoidCallback onConfirmPickup;

  @override
  Widget build(BuildContext context) {
    final pharmacy = order.pickups.firstWhereOrNull((p) => p.phId == phId);
    if (pharmacy == null) return const SizedBox.shrink();

    return Scaffold(
      body: Column(children: [
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 16, right: 16, bottom: 14),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [WTheme.aqua, WTheme.sky])),
          child: Row(children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pharmacy.name, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              Text(pharmacy.addr, style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 12)),
            ])),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('itemsToCollect'), style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.5)),
                const SizedBox(height: 10),
                ...pharmacy.items.map((name) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: (pharmacy.itemsPicked[name] == true) ? WTheme.ok.withOpacity(0.08) : WTheme.blush,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: (pharmacy.itemsPicked[name] == true) ? WTheme.ok : WTheme.cloud),
                  ),
                  child: Row(children: [
                    Icon(pharmacy.itemsPicked[name] == true ? Icons.check_box : Icons.check_box_outline_blank,
                        color: pharmacy.itemsPicked[name] == true ? WTheme.ok : WTheme.muted),
                    const SizedBox(width: 10),
                    Text(name, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: WTheme.ink)),
                  ]),
                )),
              ])),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
          child: SwipeToConfirm(
            label: context.tr('confirmPickupTemplate').replaceFirst('{name}', pharmacy.name),
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
