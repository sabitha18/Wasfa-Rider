import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';

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
