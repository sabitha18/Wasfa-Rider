import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/data/repositories/order_repository.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';

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
  final _repo = OrderRepository();

  // Week/Month tabs previously had no tap handler at all — 'Today' was
  // hardcoded as permanently active and nothing else was wired up.
  //
  // CONFIRMED real shape from GET /earnings?period=... (seen live):
  //   { "today": 334.874, "week": 334.874, "month": 335.796,
  //     "balance": ..., "paid_out": ..., "rule": {..., "value": "2.000"},
  //     "rows": [ {"amount": "334.874", "earned_on": "2026-07-14",
  //                "created_at": "2026-07-14 08:34:25", "code": "APM64", ...}, ... ] }
  // The `period` param does NOT actually filter the top-level today/week/
  // month totals — those three always come back together regardless of
  // what was requested. `rows` is the one thing that's period-scoped, and
  // is real per-delivery data — used below to build an actual chart
  // instead of the old hardcoded fake bars.
  String _period = 'today';
  bool _loadingPeriod = false;
  Map<String, dynamic>? _periodData;

  Future<void> _selectPeriod(String p) async {
    if (p == _period && _periodData != null) return;
    setState(() => _period = p);
    await _fetchPeriodData(p);
  }

  Future<void> _fetchPeriodData(String p) async {
    setState(() => _loadingPeriod = true);
    try {
      final data = await _repo.fetchEarnings(period: p);
      debugPrint('[Earnings] period=$p response: $data');
      if (!mounted) return;
      setState(() { _periodData = data; _loadingPeriod = false; });
    } catch (e) {
      debugPrint('[Earnings] period=$p FAILED: $e');
      if (!mounted) return;
      setState(() { _periodData = null; _loadingPeriod = false; });
    }
  }

  String _periodLabel(String p) => switch (p) {
    'today' => 'Today',
    'week' => context.tr('weekLabel'),
    _ => context.tr('monthLabel'),
  };

  /// Real commission total for the selected period, straight from the
  /// confirmed today/week/month keys — no more guessing at field names.
  double get _periodTotal => (_periodData?[_period] as num?)?.toDouble() ?? 0.0;

  /// Real commission rate from the backend rule, e.g. "2.000" -> 2%.
  /// Replaces whatever hardcoded percentage string was shown before.
  String? get _commissionRatePercent {
    final rule = _periodData?['rule'];
    if (rule is! Map) return null;
    final value = double.tryParse('${rule['value']}');
    if (value == null) return null;
    final type = rule['type'];
    return type == 'percent' ? '${value.toStringAsFixed(0)}%' : null;
  }

  List<Map<String, dynamic>> get _rows =>
      ((_periodData?['rows'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Builds real chart bars from the actual per-delivery rows — grouped
  /// by hour of day for Today, or by calendar day for Week/Month. Replaces
  /// the old _bars field, which was entirely hardcoded sample data that
  /// never changed no matter what was actually earned.
  List<({String h, double v})> _buildBars() {
    final rows = _rows;
    if (rows.isEmpty) return const [];

    double amountOf(Map<String, dynamic> r) => double.tryParse('${r['amount']}') ?? 0.0;

    if (_period == 'today') {
      final byHour = <int, double>{};
      for (final r in rows) {
        final createdAt = r['created_at'] as String?;
        if (createdAt == null || !createdAt.contains(' ')) continue;
        final hour = int.tryParse(createdAt.split(' ').last.split(':').first);
        if (hour == null) continue;
        byHour[hour] = (byHour[hour] ?? 0) + amountOf(r);
      }
      final hours = byHour.keys.toList()..sort();
      final maxVal = byHour.values.fold(0.0, (a, b) => a > b ? a : b);
      return hours.map((h) {
        final label = h == 0 ? '12a' : h < 12 ? '$h' : h == 12 ? '12p' : '${h - 12}p';
        return (h: label, v: maxVal > 0 ? byHour[h]! / maxVal : 0.0);
      }).toList();
    } else {
      final byDay = <String, double>{};
      for (final r in rows) {
        final day = r['earned_on'] as String?;
        if (day == null) continue;
        byDay[day] = (byDay[day] ?? 0) + amountOf(r);
      }
      final days = byDay.keys.toList()..sort();
      final maxVal = byDay.values.fold(0.0, (a, b) => a > b ? a : b);
      return days.map((d) {
        final parts = d.split('-'); // yyyy-mm-dd
        final label = parts.length == 3 ? '${parts[2]}/${parts[1]}' : d;
        return (h: label, v: maxVal > 0 ? byDay[d]! / maxVal : 0.0);
      }).toList();
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _fetchPeriodData('today'); // now fetched immediately too, so Today's chart is real from the start
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

    final isToday = _period == 'today';
    // 'today' keeps using the already-working live view-model data for its
    // headline stats (trusted existing source); week/month now use the
    // CONFIRMED real fields instead of guessed key names.
    final displayEarnings = isToday ? earnings : _periodTotal;
    final displayDeliveries = isToday ? done.length : _rows.length;
    // Failed-delivery count and total distance simply aren't present
    // anywhere in this endpoint's response — rather than show a fake or
    // wrong number for Week/Month, these stay null and render as "—".
    final int? displayFailed = isToday ? failed : null;
    final double? displayKm = isToday ? totalKm : null;
    final bars = _buildBars();

    // Was previously a hardcoded fake offset (now - 4h22m, always the same
    // regardless of when the driver actually went on shift). shift_started_at
    // is confirmed to come back from /me — now actually used.
    final shiftStart = driver?.shiftStartedAt ?? _now;
    final elapsedMin = _now.difference(shiftStart).inMinutes.clamp(0, 9999);
    final hh = elapsedMin ~/ 60;
    final mm = elapsedMin % 60;
    // Active/Idle split still has no real backend source — no endpoint
    // tracks minute-by-minute activity — so idleMin stays a placeholder.
    // Flagging this distinctly from the now-real elapsed/shift-start time
    // rather than silently leaving it looking equally legitimate.
    const idleMin = 38; // TODO: fake — no backend data source exists for this yet
    final earningPerHour = elapsedMin > 0 ? (earnings / (elapsedMin / 60)) : 0.0;

    final h = shiftStart.hour > 12 ? shiftStart.hour - 12
        : (shiftStart.hour == 0 ? 12 : shiftStart.hour);
    final ampm = shiftStart.hour < 12 ? 'AM' : 'PM';
    final shiftStartStr = driver?.shiftStartedAt != null
        ? '$h:${shiftStart.minute.toString().padLeft(2,'0')} $ampm'
        : '—'; // not on shift / backend hasn't set a start time

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
                _TabBtn(label: context.tr('myEarningsTab'),  active: _tab == 'mine',
                    activeColor: WTheme.rose,  onTap: () => setState(() => _tab = 'mine')),
                _TabBtn(label: context.tr('companyCashTab'), active: _tab == 'company',
                    activeColor: WTheme.navy,  onTap: () => setState(() => _tab = 'company')),
              ]),
            ),
            const SizedBox(height: 14),

            if (_tab == 'company') ...[
              const _CompanyCashSection(),
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
                  Text(isToday ? context.tr('myCommissionToday') : 'My commission — ${_periodLabel(_period)}',
                      style: GoogleFonts.dmSans(
                          color: Colors.white.withOpacity(0.75), fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  if (_loadingPeriod)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                    )
                  else
                    RichText(text: TextSpan(children: [
                      TextSpan(text: displayEarnings.toStringAsFixed(3), style: GoogleFonts.dmSans(
                          color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(
                          color: Colors.white.withOpacity(0.85), fontSize: 16, fontWeight: FontWeight.w600)),
                    ])),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21B47A).withOpacity(0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(context.tr('deliveriesCountTemplate').replaceFirst('{n}', '$displayDeliveries'), style: GoogleFonts.dmSans(
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
                      children: [
                        TextSpan(text: context.tr('commissionRateLine1'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        // Real rate from the backend's rule.value once loaded
                        // (confirmed live: e.g. 2%) — was a hardcoded string
                        // before, which had drifted from the real admin-set rate.
                        TextSpan(text: _commissionRatePercent != null
                            ? ' ${_commissionRatePercent!} of each order total'
                            : context.tr('commissionRatePercent')),
                      ],
                    )),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // Period tabs — previously hardcoded to always show Today
              // as active with no tap handler at all; Week/Month did
              // nothing when tapped because there was nothing to tap.
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  for (final p in ['today', 'week', 'month'])
                    Expanded(child: GestureDetector(
                      onTap: () => _selectPeriod(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _period == p ? WTheme.rose : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(child: Text(_periodLabel(p), style: GoogleFonts.dmSans(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: _period == p ? Colors.white : WTheme.muted))),
                      ),
                    )),
                ]),
              ),
              const SizedBox(height: 14),

              // Earnings breakdown chart — now built from the real `rows`
              // array (per-delivery earnings with real dates/timestamps)
              // instead of a hardcoded fake bar list that never changed.
              // Grouped by hour for Today, by day for Week/Month.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isToday ? context.tr('hourlyCap') : 'DAILY BREAKDOWN', style: GoogleFonts.dmSans(
                      fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 14),
                  if (_loadingPeriod)
                    const SizedBox(height: 118, child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
                  else if (bars.isEmpty)
                    SizedBox(
                      height: 118,
                      child: Center(child: Text(
                        _periodData == null ? "Couldn't load this data" : 'No earnings yet for this period',
                        style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, fontWeight: FontWeight.w600),
                      )),
                    )
                  else
                    SizedBox(
                      height: 118,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: bars.asMap().entries.map((e) {
                          final isLast = e.key == bars.length - 1;
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
                  _StatBox(v: '$displayDeliveries', k: context.tr('deliveriesStatLabel')),
                  _StatBox(v: displayFailed != null ? '$displayFailed' : '—', k: context.tr('failedStatLabel')),
                  _StatBox(v: displayKm != null ? '${displayKm.toStringAsFixed(1)} km' : '—', k: context.tr('distanceStatLabel')),
                  _StatBox(v: '⭐ 4.8', k: context.tr('ratingStatLabel')),
                ],
              ),
              const SizedBox(height: 20),

              // Work & hours
              Text(context.tr('workAndHours'), style: GoogleFonts.dmSans(
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
                      Text(context.tr('shiftTimeToday'), style: GoogleFonts.dmSans(
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
                      child: Text(onShift ? context.tr('liveStatus') : context.tr('pausedStatus'), style: GoogleFonts.dmSans(
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
                      _StatBox(v: '${elapsedMin - idleMin}m', k: context.tr('active')),
                      _StatBox(v: '38m', k: context.tr('idleStatLabel')),
                      _StatBox(v: earningPerHour.toStringAsFixed(2), k: context.tr('kdPerHourLabel')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: WTheme.blush, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(context.tr('shiftStarted'), style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.navy)),
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

class _CompanyCashSection extends StatefulWidget {
  const _CompanyCashSection();

  @override
  State<_CompanyCashSection> createState() => _CompanyCashSectionState();
}

class _CompanyCashSectionState extends State<_CompanyCashSection> {
  final _repo = OrderRepository();
  double? _balance;
  List<CashHandoverRecord> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final balance = await _repo.fetchCashBalance();
      final history = await _repo.fetchCashHandovers();
      if (!mounted) return;
      setState(() { _balance = balance; _history = history; _loading = false; });
    } catch (e) {
      // Backend doesn't have this built yet as of 2026-07-15 — show a
      // clear "not available" state rather than a fake number or a crash.
      debugPrint('[CompanyCash] load FAILED (expected until backend ships this): $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = 'not_ready'; });
    }
  }

  void _openQr() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CashHandoverQrScreen(
      onBack: () => Navigator.of(context).pop(),
      onConfirmed: () {
        Navigator.of(context).pop();
        _load(); // refresh real balance/history after a successful handover
      },
    )));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      // Backend doesn't have cash-balance/cash-handovers built yet.
      // Being upfront about that instead of showing fake numbers.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(children: [
          Text("Company Cash isn't available yet — check back soon",
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: Text('Retry',
              style: GoogleFonts.dmSans(color: WTheme.sky, fontWeight: FontWeight.w800))),
        ]),
      );
    }

    final companyCash = _balance ?? 0.0;
    final totalEverHanded = _history.fold(0.0, (s, h) => s + h.amount);

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
          Text(context.tr('cashToHandOver'), style: GoogleFonts.dmSans(
              color: Colors.white.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          RichText(text: TextSpan(children: [
            TextSpan(text: companyCash.toStringAsFixed(3), style: GoogleFonts.dmSans(
                color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -1)),
            TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(
                color: Colors.white.withOpacity(0.85), fontSize: 16, fontWeight: FontWeight.w600)),
          ])),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(
              context.tr('cashHandoverExplainer'),
              style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, height: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),

      // ── Action buttons or "all clear" state ──
      if (companyCash > 0) ...[
        GestureDetector(
          onTap: _openQr,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: WTheme.ok,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: WTheme.ok.withOpacity(0.4), blurRadius: 28, offset: const Offset(0, 12))],
            ),
            child: Center(child: Text(context.tr('showQrToManager'), style: GoogleFonts.dmSans(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          // Bank withdrawal flow wasn't part of what backend spec'd — left
          // as a toast until that gets designed separately.
          onTap: () => showWToast(context, context.tr('bankWithdrawToast')),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WTheme.navy, width: 1.5),
              boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Center(child: Text(context.tr('withdrawToBank'), style: GoogleFonts.dmSans(
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
          child: Center(child: Text(context.tr('allClearNoCash'), style: GoogleFonts.dmSans(
              color: WTheme.ok, fontWeight: FontWeight.w700, fontSize: 13))),
        ),
      ],
      const SizedBox(height: 20),

      // ── Recent handovers ──
      Align(alignment: Alignment.centerLeft,
        child: Text(context.tr('recentHandovers'), style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
      ),
      const SizedBox(height: 8),

      if (_history.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Center(child: Text(context.tr('noHandoversYet'),
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 12))),
        )
      else ...[
        for (final h in _history) _HandoverCard(handover: h),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(context.tr('totalHandedOver'), style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: WTheme.navy)),
            Text('${totalEverHanded.toStringAsFixed(3)} KD', style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
          ]),
        ),
      ],
    ]);
  }
}

// ── Real-time cash handover QR/code screen ──────────────────────
// Backend endpoints for this don't exist yet (as of 2026-07-15) — every
// call here will fail gracefully with a clear "not available" message
// until they do. Built ahead of time so it's ready to go the moment
// they ship, matching the confirmed decisions: QR encodes a full link
// (dispatcher scans with their phone's own camera, no custom scanner
// needed since they only have a dashboard, not an app), plus a 6-digit
// manual-entry fallback. Client-side decision: always request a brand
// new session the instant the local 2-minute countdown hits zero,
// rather than assuming anything about how backend manages expiry
// internally — simplest, most robust behavior regardless of what
// backend does on their end.
class CashHandoverQrScreen extends StatefulWidget {
  const CashHandoverQrScreen({super.key, required this.onBack, required this.onConfirmed});
  final VoidCallback onBack;
  final VoidCallback onConfirmed;

  @override
  State<CashHandoverQrScreen> createState() => _CashHandoverQrScreenState();
}

class _CashHandoverQrScreenState extends State<CashHandoverQrScreen> {
  final _repo = OrderRepository();
  CashHandoverSession? _session;
  bool _loading = true;
  bool _confirmed = false;
  String? _error;
  Timer? _countdownTimer;
  Timer? _statusPollTimer;
  int _secondsLeft = 120;

  @override
  void initState() {
    super.initState();
    _startNewSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startNewSession() async {
    setState(() { _loading = true; _error = null; });
    try {
      final session = await _repo.startCashHandover();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
        _secondsLeft = session.expiresAt != null
            ? session.expiresAt!.difference(DateTime.now()).inSeconds.clamp(0, 999)
            : 120;
      });
      _startTimers();
    } catch (e) {
      debugPrint('[CashHandover] startCashHandover FAILED (expected until backend ships this): $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = "This isn't available yet — check back soon."; });
    }
  }

  void _startTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        setState(() => _secondsLeft = 0);
        _startNewSession(); // client-decided: always get a fresh one on local expiry
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    final session = _session;
    if (session == null || _confirmed) return;
    try {
      final status = await _repo.getCashHandoverStatus(session.id);
      if (!mounted) return;
      if (status == 'confirmed') {
        _countdownTimer?.cancel();
        _statusPollTimer?.cancel();
        setState(() => _confirmed = true);
      } else if (status == 'expired') {
        _startNewSession();
      }
    } catch (e) {
      debugPrint('[CashHandover] status check failed (will retry next tick): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WTheme.blush,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: WTheme.navy), onPressed: widget.onBack),
        title: Text('Hand Over Cash', style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _confirmed ? _buildConfirmed()
              : _loading ? const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: CircularProgressIndicator())
              : _error != null ? _buildError()
              : _buildSession(),
        )),
      ),
    );
  }

  Widget _buildError() => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 14)),
    const SizedBox(height: 16),
    TextButton(onPressed: _startNewSession, child: Text('Retry',
        style: GoogleFonts.dmSans(color: WTheme.sky, fontWeight: FontWeight.w800))),
  ]);

  Widget _buildConfirmed() => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 80, height: 80,
        decoration: const BoxDecoration(color: WTheme.ok, shape: BoxShape.circle),
        child: const Icon(Icons.check, color: Colors.white, size: 44)),
    const SizedBox(height: 16),
    Text('Handed over!', style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 20)),
    const SizedBox(height: 8),
    Text('${_session?.amount.toStringAsFixed(3) ?? "—"} KD cleared from your balance',
        textAlign: TextAlign.center, style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13)),
    const SizedBox(height: 24),
    ElevatedButton(
      onPressed: widget.onConfirmed,
      style: ElevatedButton.styleFrom(backgroundColor: WTheme.ok, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: Text('Done', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
    ),
  ]);

  Widget _buildSession() {
    final session = _session!;
    final mm = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (_secondsLeft % 60).toString().padLeft(2, '0');
    return Column(children: [
      Text('${session.amount.toStringAsFixed(3)} KD', style: GoogleFonts.dmSans(
          color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 32)),
      const SizedBox(height: 4),
      Text('Show this to your dispatcher', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13)),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 10))]),
        child: session.qrData.isNotEmpty
            ? QrImageView(data: session.qrData, version: QrVersions.auto, size: 220)
            : SizedBox(width: 220, height: 220, child: Center(child: Text('QR unavailable',
            style: GoogleFonts.dmSans(color: WTheme.muted)))),
      ),
      const SizedBox(height: 20),
      Text('or enter this code manually', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 12)),
      const SizedBox(height: 8),
      Text(
        session.code.isNotEmpty ? session.code.split('').join(' ') : '——————',
        style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 30, letterSpacing: 4),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(999)),
        child: Text('Expires in $mm:$ss', style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
      const SizedBox(height: 8),
      Text('A new code generates automatically when this expires',
          textAlign: TextAlign.center, style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
    ]);
  }
}

// ── Handover history card ────────────────────────────────────────
class _HandoverCard extends StatelessWidget {
  const _HandoverCard({required this.handover});
  final CashHandoverRecord handover;

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
              TextSpan(text: ' ${context.tr('kd')}', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
            ])),
            if (handover.isBank) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(999)),
                child: Text(context.tr('bankBadge'), style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w800, color: WTheme.navy, letterSpacing: 0.4)),
              ),
            ],
          ]),
          const SizedBox(height: 3),
          Text('${handover.dateLabel} · ${handover.confirmedBy ?? "—"}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(999)),
          child: Text(handover.pending ? context.tr('pendingBadge') : context.tr('confirmedBadge'), style: GoogleFonts.dmSans(
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
