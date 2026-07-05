import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.onTabChange});
  final ValueChanged<String> onTabChange;

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  String _tab = 'mine';
  late Timer _timer;
  DateTime _now = DateTime.now();
  late final DateTime _shiftStart;

  final _bars = [
    (h: '9',  v: 0.30), (h: '10', v: 0.53), (h: '11', v: 0.76),
    (h: '12', v: 0.99), (h: '1',  v: 0.46), (h: '2',  v: 0.69),
    (h: '3',  v: 0.92), (h: '4',  v: 0.62),
  ];

  @override
  void initState() {
    super.initState();
    _shiftStart = DateTime.now().subtract(const Duration(hours: 4, minutes: 22));
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appVM    = context.watch<AppViewModel>();
    final ordersVM = context.watch<OrdersViewModel>();
    final driver   = appVM.driver;
    final earnings = driver?.todayEarnings ?? 0.0;
    final onShift  = driver?.onShift ?? false;

    final done   = ordersVM.orders.where((o) => o.status == OrderStatus.done).toList();
    final failed = ordersVM.orders.where((o) => o.status == OrderStatus.failed).length;
    final totalKm = done.fold(0.0, (s, o) => s + o.distanceKm);

    final elapsedMin = _now.difference(_shiftStart).inMinutes.clamp(0, 9999);
    final hh = elapsedMin ~/ 60;
    final mm = elapsedMin % 60;
    const idleMin = 38;
    final earningPerHour = elapsedMin > 0 ? (earnings / (elapsedMin / 60)) : 0.0;

    final h = _shiftStart.hour > 12 ? _shiftStart.hour - 12
        : (_shiftStart.hour == 0 ? 12 : _shiftStart.hour);
    final ampm = _shiftStart.hour < 12 ? 'AM' : 'PM';
    final shiftStartStr = '$h:${_shiftStart.minute.toString().padLeft(2,'0')} $ampm';

    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        RiderRibbon(
          earnings: earnings,
          deliveries: driver?.deliveriesToday ?? 0,
          onShift: onShift,
          onToggleShift: appVM.toggleShift,
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          children: [
            // Tab switcher
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                _TabBtn(label: '💰 My Earnings',  active: _tab == 'mine',
                    activeColor: WTheme.rose,  onTap: () => setState(() => _tab = 'mine')),
                _TabBtn(label: '🏦 Company Cash', active: _tab == 'company',
                    activeColor: WTheme.navy,  onTap: () => setState(() => _tab = 'company')),
              ]),
            ),
            const SizedBox(height: 14),

            if (_tab == 'company') ...[
              _CompanyCashSection(earnings: earnings, done: done.length),
            ] else ...[
              // My Earnings hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF023B60), Color(0xFF1E9CD7)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.30), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('MY COMMISSION TODAY', style: GoogleFonts.dmSans(
                      color: Colors.white.withOpacity(0.75), fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: earnings.toStringAsFixed(3), style: GoogleFonts.dmSans(
                        color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    TextSpan(text: ' KD', style: GoogleFonts.dmSans(
                        color: Colors.white.withOpacity(0.85), fontSize: 16, fontWeight: FontWeight.w600)),
                  ])),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21B47A).withOpacity(0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('↑ ${done.length} deliveries', style: GoogleFonts.dmSans(
                        color: const Color(0xFFB7F5CE), fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: RichText(text: TextSpan(
                      style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.90), fontSize: 11),
                      children: const [
                        TextSpan(text: 'Your commission rate (set by admin):\n',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: '10% of each order total'),
                      ],
                    )),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // Period tabs
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  for (final e in [('Today', true), ('Week', false), ('Month', false)])
                    Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: e.$2 ? WTheme.rose : Colors.transparent,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(child: Text(e.$1, style: GoogleFonts.dmSans(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: e.$2 ? Colors.white : WTheme.muted))),
                    )),
                ]),
              ),
              const SizedBox(height: 14),

              // Hourly bar chart
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('HOURLY', style: GoogleFonts.dmSans(
                      fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 118,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _bars.asMap().entries.map((e) {
                        final isLast = e.key == _bars.length - 1;
                        return Expanded(child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                            Expanded(child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: e.value.v,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                      colors: isLast
                                          ? [WTheme.rose, const Color(0xFFC84686)]
                                          : [WTheme.aqua, WTheme.sky],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            )),
                            const SizedBox(height: 4),
                            Text(e.value.h, style: GoogleFonts.dmSans(
                                fontSize: 9, color: WTheme.muted, fontWeight: FontWeight.w700)),
                          ]),
                        ));
                      }).toList(),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // Stats 2×2 grid
              GridView.count(
                crossAxisCount: 2, shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12, mainAxisSpacing: 12,
                childAspectRatio: 2.4,
                children: [
                  _StatBox(v: '${done.length}', k: 'Deliveries'),
                  _StatBox(v: '$failed', k: 'Failed'),
                  _StatBox(v: '${totalKm.toStringAsFixed(1)} km', k: 'Distance'),
                  const _StatBox(v: '⭐ 4.8', k: 'Rating'),
                ],
              ),
              const SizedBox(height: 20),

              // Work & hours
              Text('WORK & HOURS', style: GoogleFonts.dmSans(
                  fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Column(children: [
                  Row(children: [
                    Container(
                      width: 54, height: 54,
                      decoration: BoxDecoration(
                        color: onShift ? WTheme.ok.withOpacity(0.12) : WTheme.warn.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(child: Text('⏱', style: TextStyle(
                          fontSize: 26, color: onShift ? WTheme.ok : const Color(0xFFB4730E)))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SHIFT TIME TODAY', style: GoogleFonts.dmSans(
                          fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text('${hh}h ${mm.toString().padLeft(2,'0')}m', style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 22, letterSpacing: -0.4)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: onShift ? WTheme.ok.withOpacity(0.13) : WTheme.warn.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(onShift ? '● LIVE' : '◯ PAUSED', style: GoogleFonts.dmSans(
                          fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4,
                          color: onShift ? WTheme.ok : const Color(0xFFB4730E))),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 3, shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8, mainAxisSpacing: 8,
                    childAspectRatio: 1.5,
                    children: [
                      _StatBox(v: '${elapsedMin - idleMin}m', k: 'Active'),
                      const _StatBox(v: '38m', k: 'Idle'),
                      _StatBox(v: earningPerHour.toStringAsFixed(2), k: 'KD / hour'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: WTheme.blush, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Shift started', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.navy)),
                      Text(shiftStartStr, style: GoogleFonts.dmSans(
                          fontSize: 11, fontWeight: FontWeight.w800, color: WTheme.navy)),
                    ]),
                  ),
                ]),
              ),
            ],
          ],
        )),
        RiderBottomNav(current: 'earnings', onChanged: widget.onTabChange),
      ]),
    );
  }
}

class _CompanyCashSection extends StatelessWidget {
  const _CompanyCashSection({required this.earnings, required this.done});
  final double earnings;
  final int done;

  // Mock handover history until a real companyCash/handoverHistory model exists
  static final List<_CashHandover> _mockHistory = [
    _CashHandover(amount: 86.000, isBank: false, dateLabel: 'May 18, 11:00 PM', confirmedBy: 'Saud Q.', pending: false),
    _CashHandover(amount: 124.500, isBank: false, dateLabel: 'May 17, 11:12 PM', confirmedBy: 'Saud Q.', pending: false),
    _CashHandover(amount: 92.250, isBank: false, dateLabel: 'May 16, 10:44 PM', confirmedBy: 'Maryam B.', pending: false),
  ];

  double get _companyCash => earnings > 0 ? 38.100 : 0.0; // placeholder cash-to-hand-over total

  @override
  Widget build(BuildContext context) {
    final totalEverHanded = _mockHistory.fold(0.0, (s, h) => s + h.amount);

    return Column(children: [
      // ── Cash to hand over hero ──
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF023B60), Color(0xFF04527F)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.30), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CASH TO HAND OVER', style: GoogleFonts.dmSans(
              color: Colors.white.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          RichText(text: TextSpan(children: [
            TextSpan(text: _companyCash.toStringAsFixed(3), style: GoogleFonts.dmSans(
                color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -1)),
            TextSpan(text: ' KD', style: GoogleFonts.dmSans(
                color: Colors.white.withOpacity(0.85), fontSize: 16, fontWeight: FontWeight.w600)),
          ])),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '💡 This is the cash you collected from CASH-paid orders.\nHand it over to your manager — they scan the QR — and it clears.',
              style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, height: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // ── Action buttons or "all clear" state ──
      if (_companyCash > 0) ...[
        GestureDetector(
          onTap: () => showWToast(context, '📷 Cash handover QR — show to manager to confirm'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: WTheme.ok,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: WTheme.ok.withOpacity(0.4), blurRadius: 28, offset: const Offset(0, 12))],
            ),
            child: Center(child: Text('📷 Show QR to manager & hand over', style: GoogleFonts.dmSans(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => showWToast(context, '🏦 Bank withdraw — attach receipt to continue'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WTheme.navy, width: 1.5),
              boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Center(child: Text('🏦 Withdraw to bank — attach receipt', style: GoogleFonts.dmSans(
                color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 14))),
          ),
        ),
      ] else ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WTheme.ok.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WTheme.ok, width: 1.5),
          ),
          child: Center(child: Text('✓ All clear — no cash to hand over', style: GoogleFonts.dmSans(
              color: WTheme.ok, fontWeight: FontWeight.w700, fontSize: 13))),
        ),
      ],
      const SizedBox(height: 20),

      // ── Recent handovers ──
      Align(alignment: Alignment.centerLeft,
        child: Text('RECENT HANDOVERS', style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
      ),
      const SizedBox(height: 8),

      if (_mockHistory.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text('No handovers yet. Once you hand over cash, history appears here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 12))),
        )
      else ...[
        for (final h in _mockHistory) _HandoverCard(handover: h),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total handed over', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: WTheme.navy)),
            Text('${totalEverHanded.toStringAsFixed(3)} KD', style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
          ]),
        ),
      ],
    ]);
  }
}

// ── Handover record (mock model) ────────────────────────────────
class _CashHandover {
  final double amount;
  final bool isBank;
  final String dateLabel;
  final String confirmedBy;
  final bool pending;
  const _CashHandover({
    required this.amount, required this.isBank,
    required this.dateLabel, required this.confirmedBy, required this.pending,
  });
}

class _HandoverCard extends StatelessWidget {
  const _HandoverCard({required this.handover});
  final _CashHandover handover;

  @override
  Widget build(BuildContext context) {
    final edgeColor = handover.pending ? WTheme.warn : WTheme.ok;
    final tagBg = handover.pending ? WTheme.warn.withOpacity(0.15) : WTheme.ok.withOpacity(0.15);
    final tagFg = handover.pending ? const Color(0xFFB4730E) : WTheme.ok;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: edgeColor, width: 4)),
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(handover.isBank ? '🏦' : '💵', style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            RichText(text: TextSpan(children: [
              TextSpan(text: handover.amount.toStringAsFixed(3), style: GoogleFonts.dmSans(
                  color: WTheme.navy, fontWeight: FontWeight.w700, fontSize: 13)),
              TextSpan(text: ' KD', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
            ])),
            if (handover.isBank) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(999)),
                child: Text('BANK', style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w800, color: WTheme.navy, letterSpacing: 0.4)),
              ),
            ],
          ]),
          const SizedBox(height: 3),
          Text('${handover.dateLabel} · ${handover.confirmedBy}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(999)),
          child: Text(handover.pending ? '⏳ PENDING' : '✓ CONFIRMED', style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w800, color: tagFg, letterSpacing: 0.3)),
        ),
      ]),
    );
  }
}

class _TabBtn extends StatelessWidget {
  const _TabBtn({required this.label, required this.active,
    required this.activeColor, required this.onTap});
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: active ? activeColor : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(child: Text(label, style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: active ? Colors.white : WTheme.muted))),
    ),
  ));
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.v, required this.k});
  final String v, k;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(color: WTheme.blush, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(v, style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 17, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text(k.toUpperCase(), style: GoogleFonts.dmSans(
              fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
  );
}
