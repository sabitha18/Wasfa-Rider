import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    required this.onTabChange,
    required this.onOpenOrder,
    required this.onOpenBatchPickup,
    required this.onCallNow,
    required this.onOpenMap,
    required this.onOpenMultiPickup,
  });
  final ValueChanged<String> onTabChange;
  final ValueChanged<String> onOpenOrder;
  final VoidCallback onOpenBatchPickup;
  final ValueChanged<String> onCallNow;
  final ValueChanged<Order> onOpenMap;
  // CLIENT-REQUESTED (2026-08-19): tapping the "N pharmacies" chip on a
  // multi-pharmacy order opens that order's own pickup checklist.
  final ValueChanged<String> onOpenMultiPickup;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _filter = 'active';
  Order? _addrOrder;

  // ── Date filter state ──
  String _dateFilter = 'today'; // 'today', 'yesterday', 'week', 'all', 'custom'
  DateTime? _customDate;

  // CLIENT-REQUESTED (2026-08-31): "for active use active api, for all
  // use all api, for done use done api, and the count and all from api"
  // — fetches all three tabs on screen open, so every tab's label shows
  // its own real, accurate count immediately, even though only one
  // tab's list is actually visible at a time. See OrdersViewModel's
  // loadTab for how each tab's data is kept fully independent.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAllTabs());
  }

  String _fmtDateParam(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// CLIENT-ASKED (2026-08-31): computes the exact date_from/date_to
  /// this screen's currently-selected date filter maps to, matching
  /// what was requested from Soumya — same value twice for a single day
  /// (Today/Yesterday/a custom pick), a real range for This Week, and
  /// neither param at all for "All" (no filter — don't restrict at all).
  (String?, String?) _computeDateRange() {
    final now = DateTime.now();
    if (_customDate != null) {
      final s = _fmtDateParam(_customDate!);
      return (s, s);
    }
    switch (_dateFilter) {
      case 'today':
        final s = _fmtDateParam(now);
        return (s, s);
      case 'yesterday':
        final s = _fmtDateParam(now.subtract(const Duration(days: 1)));
        return (s, s);
      case 'week':
        return (_fmtDateParam(now.subtract(const Duration(days: 7))), _fmtDateParam(now));
      default:
        return (null, null); // 'all' — no date restriction
    }
  }

  /// Re-fetches all three tabs using the currently-selected date range —
  /// called on screen open and whenever the date filter itself changes,
  /// so every tab's count and list both reflect the active date filter
  /// once backend support for date_from/date_to is confirmed live. The
  /// existing client-side _matchesDate filter (used by _filtered/_count
  /// below) stays in place regardless, as a safety net either way.
  void _reloadAllTabs() {
    final vm = context.read<OrdersViewModel>();
    final (from, to) = _computeDateRange();
    vm.loadTab('active', dateFrom: from, dateTo: to);
    vm.loadTab('done', dateFrom: from, dateTo: to);
    vm.loadTab('all', dateFrom: from, dateTo: to);
  }

  bool _matchesDate(Order o) {
    final now = DateTime.now();
    final d = o.createdAt;
    if (_customDate != null) {
      return d.year == _customDate!.year &&
          d.month == _customDate!.month &&
          d.day == _customDate!.day;
    }
    switch (_dateFilter) {
      case 'today':
        return d.year == now.year && d.month == now.month && d.day == now.day;
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        return d.year == y.year && d.month == y.month && d.day == y.day;
      case 'week':
        final weekAgo = now.subtract(const Duration(days: 7));
        return d.isAfter(weekAgo);
      default:
        return true; // 'all'
    }
  }

  // CLIENT-REQUESTED (2026-08-31): now that each tab's orders come
  // directly from that tab's own dedicated endpoint (vm.ordersForTab),
  // the status filtering that used to happen here is already done —
  // backend's own tab=active/done/all response only ever contains that
  // tab's own orders. The only filtering still needed client-side is
  // the date filter (Today/Yesterday/This Week), since the API has no
  // date parameter at all.
  List<Order> _filtered(List<Order> orders) => orders.where(_matchesDate).toList();

  int _count(OrdersViewModel vm, String f) {
    // CLIENT-REQUESTED (2026-08-31): "for active use active api, for
    // all use all api, for done use done api, and the count and all
    // from api" — each tab's count comes directly from THAT tab's own
    // dedicated fetch (vm.countsForTab), which is now sent WITH the
    // current date range on every request. CLIENT-CONFIRMED (2026-09-01):
    // backend now correctly applies date_from/date_to server-side (a
    // date-filtered request returned an order matching that exact date)
    // — so the counts object returned for ANY request, date-filtered or
    // not, is already correctly scoped to that same request's own date
    // range. No client-side fallback needed anymore: always show
    // exactly what the API returned for this tab.
    final serverCounts = vm.countsForTab(f);
    return serverCounts[f] ?? 0;
  }

  Color _edgeColor(Order o) => switch (o.status) {
    OrderStatus.active => WTheme.rose,
    OrderStatus.next   => WTheme.navy,
    OrderStatus.done   => WTheme.ok,
    OrderStatus.failed => WTheme.err,
    _                  => WTheme.cloud,
  };

  @override
  Widget build(BuildContext context) {
    final appVM    = context.watch<AppViewModel>();
    final vm       = context.watch<OrdersViewModel>();
    final driver   = appVM.driver;
    final orders   = vm.ordersForTab(_filter);
    final filtered = _filtered(orders);
    final canReorder = _filter == 'active' && filtered.length > 1;

    return Scaffold(
      body: Stack(children: [
        Column(children: [
          RiderRibbon(
            earnings: driver?.todayEarnings ?? 0,
            deliveries: driver?.deliveriesToday ?? 0,
            onShift: driver?.onShift ?? false,
            onToggleShift: appVM.toggleShift,
          ),
          Expanded(child: canReorder
              ? _buildReorderableList(filtered, vm, orders)
              : _buildNormalList(filtered, vm, orders)),
          RiderBottomNav(current: 'orders', onChanged: widget.onTabChange),
        ]),
        if (_addrOrder != null)
          Positioned.fill(
            child: _AddressPopup(
              order: _addrOrder!,
              onClose: () => setState(() => _addrOrder = null),
              onOpenMap: widget.onOpenMap,
            ),
          ),
      ]),
    );
  }

  // ── Headers ───────────────────────────────────────────────────
  List<Widget> _headers(List<Order> orders, OrdersViewModel vm) {
    final canReorder = _filter == 'active' && _filtered(orders).length > 1;
    return [
      if (vm.batchOrderIds.isNotEmpty)
        _BatchGroupHeader(
          batchOrderIds: vm.batchOrderIds,
          pharmacyName: vm.batchPharmacyName ?? '',
          pharmacyAddr: vm.batchPharmacyAddr ?? '',
          // CLIENT-REQUESTED (2026-08-31): now that each tab has its own
          // independent data, this specifically needs the active tab's
          // orders regardless of which tab the driver currently has
          // selected — a batch is inherently active work, so it should
          // never disappear or show stale data just because the driver
          // happens to be looking at the Done tab right now.
          orders: vm.ordersForTab('active'),
          pickedUp: vm.batchPickedUp,
          onTap: widget.onOpenBatchPickup,
        ),
      _FilterTabs(filter: _filter, count: _count, vm: vm,
          onChanged: (f) {
            setState(() => _filter = f);
            // CLIENT-REQUESTED (2026-08-31): "for active use active
            // api, for all use all api, for done use done api" — every
            // tab switch re-fetches that specific tab fresh from its
            // own dedicated endpoint, rather than relying on whatever
            // was loaded earlier. All three tabs are also already
            // pre-loaded once on screen open (see initState above) so
            // every tab's count is accurate immediately, even before
            // the driver has switched to it. Also passes the currently-
            // active date filter through — switching status tabs should
            // never silently drop whatever date range (Today/This Week/
            // custom) was already selected.
            final (from, to) = _computeDateRange();
            vm.loadTab(f, dateFrom: from, dateTo: to);
          }),
      const SizedBox(height: 10),
      _DateFilterRow(
        dateFilter: _dateFilter,
        customDate: _customDate,
        onChanged: (f) {
          setState(() {
            _dateFilter = f;
            _customDate = null;
          });
          // CLIENT-ASKED (2026-08-31): re-fetch all three tabs with the
          // newly-selected date range, once backend support for
          // date_from/date_to is confirmed live — see fetchOrders's own
          // doc for the full context on this ask.
          _reloadAllTabs();
        },
        onPickCustom: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _customDate ?? DateTime.now(),
            firstDate: DateTime(2023, 1, 1),
            lastDate: DateTime.now(),
            builder: (context, child) => Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: WTheme.rose,
                  onPrimary: Colors.white,
                  onSurface: WTheme.navy,
                ),
              ),
              child: child!,
            ),
          );
          if (picked != null) {
            setState(() {
              _customDate = picked;
              _dateFilter = 'custom';
            });
            _reloadAllTabs();
          }
        },
        onClearCustom: () {
          setState(() {
            _customDate = null;
            _dateFilter = 'all';
          });
          _reloadAllTabs();
        },
      ),
      const SizedBox(height: 14),
      if (canReorder)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(children: [
            Text('≡', style: TextStyle(color: WTheme.muted, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('HOLD ≡ ON THE RIGHT EDGE TO DRAG AND REORDER',
                style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted,
                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ]),
        ),
    ];
  }

  // ── Reorderable list (active tab with multiple cards) ─────────
  Widget _buildReorderableList(List<Order> filtered, OrdersViewModel vm, List<Order> orders) {
    // CLIENT-REPORTED (2026-08-18): confirmed on video — dragging an
    // order card could visually slide it clear past the Active/Done/All
    // tabs and date filter chips, landing ABOVE them (or sandwiching
    // them between two cards mid-drag). Root cause: those headers were
    // rendered as ordinary children INSIDE the same ReorderableListView
    // as the cards — wrapped in _NonDraggableItem, but that wrapper was
    // a complete no-op (just `Widget build(context) => child;`), so it
    // never actually stopped a dragged card from being reordered around
    // them. The only real fix is structural: headers now live in a
    // fixed Column ABOVE the ReorderableListView entirely, not as fake
    // "header items" within it — a drag can't visually reach an area
    // it isn't part of the same scrollable/reorderable widget as.
    final headers = _headers(orders, vm);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(children: headers),
      ),
      Expanded(
        child: RefreshIndicator(
          color: WTheme.rose,
          onRefresh: () {
            // Same fix as _buildNormalList's RefreshIndicator — this
            // list is always the active tab specifically (reorder only
            // ever applies there), so re-fetch that tab directly rather
            // than the old, now-unrelated vm.refresh().
            final (from, to) = _computeDateRange();
            return vm.loadTab('active', dateFrom: from, dateTo: to);
          },
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            buildDefaultDragHandles: false,
            onReorder: (oldIdx, newIdx) async {
              // No more header-offset math needed — this list now only
              // ever contains order cards, so oldIdx/newIdx map directly.
              final from = oldIdx;
              var to = newIdx;
              if (from < 0 || from >= filtered.length) return;
              if (to > from) to -= 1;
              to = to.clamp(0, filtered.length - 1);
              final ids = filtered.map((o) => o.id).toList();
              ids.insert(to, ids.removeAt(from));
              // SUPERSEDED (2026-08-18): the per-order position endpoint
              // is gone — client confirmed the new bulk endpoint
              // replaces it entirely, taking the whole new sequence in
              // one call instead of needing a loop of calls for anything
              // beyond a single swap.
              // CLIENT-REPORTED separately: this toast used to fire
              // unconditionally the instant the drag ended, regardless
              // of whether the backend sync succeeded. Now waits for
              // the real result: an honest "not saved" warning when it
              // fails, instead of a success message that wasn't
              // actually true.
              final synced = await vm.reorderActive(ids);
              if (!context.mounted) return;
              if (synced) {
                showWToast(context, '🔢 Order sequence updated — next stop is now #1');
              } else {
                showWToast(context, "⚠️ Reordered on your device, but couldn't save it yet — it may revert on refresh");
              }
            },
            children: [
              ...filtered.asMap().entries.map((e) {
                final idx = e.key;
                final o   = e.value;
                // Pass dragIndex so the card renders the ≡ handle inside itself
                return _buildCardWidget(o, vm, dragIndex: idx);
              }),
              if (filtered.isEmpty)
                _NonDraggableItem(key: const ValueKey('empty'), child: _emptyState()),
            ],
          ),
        ),
      ),
    ]);
  }

  // ── Normal scroll list (done/all tab) ─────────────────────────
  Widget _buildNormalList(List<Order> filtered, OrdersViewModel vm, List<Order> orders) {
    // CLIENT-REPORTED (2026-09-01): pull-to-refresh appeared to do
    // nothing. Root cause: this called vm.refresh(), which only updates
    // the OLD shared _orders list — but since the per-tab rework, this
    // screen displays vm.ordersForTab(_filter) instead, a completely
    // different list that vm.refresh() never touches at all. Fixed to
    // re-fetch THIS tab specifically, with whatever date range is
    // currently active.
    final isLoading = vm.isLoadingTab(_filter);
    return RefreshIndicator(
      color: WTheme.rose,
      onRefresh: () {
        final (from, to) = _computeDateRange();
        return vm.loadTab(_filter, dateFrom: from, dateTo: to);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        children: [
          ..._headers(orders, vm),
          ...filtered.map((o) => _buildCardWidget(o, vm)),
          if (filtered.isEmpty) (isLoading ? _loadingState() : _emptyState()),
        ],
      ),
    );
  }

  Widget _buildCardWidget(Order o, OrdersViewModel vm, {int? dragIndex}) => _OrderListCard(
    key: ValueKey('card_${o.id}'),
    order: o,
    edgeColor: _edgeColor(o),
    dragIndex: dragIndex,
    onTap: () => widget.onOpenOrder(o.id),
    onCallNow: o.hasPendingCallRequest ? () => widget.onCallNow(o.id) : null,
    onCancelEscalation: o.hasPendingEscalation ? () => vm.cancelEscalation(o.id) : null,
    onOpenMap: () => widget.onOpenMap(o),
    onCallCustomer: () async {
      final url = 'tel:${o.phone.replaceAll(RegExp(r'\s'), '')}';
      if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
    },
    onShowAddress: () => setState(() => _addrOrder = o),
    onOpenMultiPickup: () => widget.onOpenMultiPickup(o.id),
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      const Text('📋', style: TextStyle(fontSize: 32)),
      const SizedBox(height: 10),
      Text(context.tr('noOrdersYet'),
          style: GoogleFonts.dmSans(color: WTheme.muted, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _loadingState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: WTheme.rose)),
      const SizedBox(height: 14),
      Text(context.tr('loading'),
          style: GoogleFonts.dmSans(color: WTheme.muted, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ── Non-draggable wrapper for header items in ReorderableListView ─
class _NonDraggableItem extends StatelessWidget {
  const _NonDraggableItem({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

// ── Filter Tabs ────────────────────────────────────────────────
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.filter, required this.count, required this.onChanged, required this.vm});
  final String filter;
  final int Function(OrdersViewModel, String) count;
  final ValueChanged<String> onChanged;
  final OrdersViewModel vm;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      for (final f in [('active', context.tr('active')), ('done', context.tr('done')), ('all', context.tr('all'))])
        Expanded(child: GestureDetector(
          onTap: () => onChanged(f.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: filter == f.$1 ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: filter == f.$1
                  ? [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 6)]
                  : [],
            ),
            child: Center(child: Text('${f.$2} (${count(vm, f.$1)})',
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700,
                    color: filter == f.$1 ? WTheme.rose : WTheme.muted))),
          ),
        )),
    ]),
  );
}

// ── Date Filter Row ─────────────────────────────────────────────
class _DateFilterRow extends StatelessWidget {
  const _DateFilterRow({
    required this.dateFilter,
    required this.customDate,
    required this.onChanged,
    required this.onPickCustom,
    required this.onClearCustom,
  });
  final String dateFilter;
  final DateTime? customDate;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickCustom;
  final VoidCallback onClearCustom;

  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  String _fmtCustom(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final options = [
      ('today', context.tr('todayFilter')),
      ('yesterday', context.tr('yesterday')),
      ('week', context.tr('thisWeek')),
      ('all', context.tr('all')),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final o in options) ...[
          _DateChip(
            label: o.$2,
            selected: dateFilter == o.$1 && customDate == null,
            onTap: () => onChanged(o.$1),
          ),
          const SizedBox(width: 8),
        ],
        // Custom date picker chip — shows the picked date, tap × to clear
        GestureDetector(
          onTap: customDate != null ? null : onPickCustom,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: customDate != null ? WTheme.rose : WTheme.cloud,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(customDate != null ? '📅 ${_fmtCustom(customDate!)}' : '📅 Pick date',
                  style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700,
                      color: customDate != null ? Colors.white : WTheme.muted)),
              if (customDate != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClearCustom,
                  child: const Text('×', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? WTheme.navy : WTheme.cloud,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: GoogleFonts.dmSans(
        fontSize: 12, fontWeight: FontWeight.w700,
        color: selected ? Colors.white : WTheme.muted,
      )),
    ),
  );
}

// ── Order List Card ────────────────────────────────────────────
class _OrderListCard extends StatelessWidget {
  const _OrderListCard({
    super.key,
    required this.order,
    required this.onTap,
    required this.edgeColor,
    this.dragIndex,
    this.onCallNow,
    this.onCancelEscalation,
    this.onOpenMap,
    this.onCallCustomer,
    this.onShowAddress,
    this.onOpenMultiPickup,
  });
  final Order order;
  final VoidCallback onTap;
  final Color edgeColor;
  final int? dragIndex;          // non-null = show ≡ drag handle
  final VoidCallback? onCallNow, onCancelEscalation, onOpenMap, onCallCustomer, onShowAddress, onOpenMultiPickup;

  @override
  Widget build(BuildContext context) {
    final isActive = order.status == OrderStatus.active;
    final isDone   = order.status == OrderStatus.done || order.status == OrderStatus.failed;
    final hasCall  = order.hasPendingCallRequest || order.hasPendingEscalation;
    const cardRadius = 16.0;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isDone ? 0.82 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardRadius),
            boxShadow: [BoxShadow(
              color: hasCall ? WTheme.rose.withOpacity(0.25) : WTheme.navy.withOpacity(0.08),
              blurRadius: hasCall ? 18 : 12,
              offset: const Offset(0, 4),
            )],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(cardRadius),
            child: Stack(children: [
              // Base card: background + rounded outer border + all content
              Container(
                decoration: BoxDecoration(
                  gradient: isActive
                      ? LinearGradient(
                      colors: [WTheme.rose.withOpacity(0.08), Colors.white],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                      : null,
                  color: isActive ? null : Colors.white,
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(color: WTheme.navy.withOpacity(0.15), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Row 1: ID + total + optional drag handle
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('#${order.id}', style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700, color: WTheme.navy.withOpacity(0.75),
                          fontSize: 14, letterSpacing: -0.2)),
                      Row(children: [
                        RichText(text: TextSpan(children: [
                          TextSpan(text: order.total.toStringAsFixed(3),
                              style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy,
                                  fontSize: 17, letterSpacing: -0.3)),
                          TextSpan(text: ' KD',
                              style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted,
                                  fontWeight: FontWeight.w600)),
                        ])),
                        if (dragIndex != null) ...[
                          const SizedBox(width: 8),
                          ReorderableDragStartListener(
                            index: dragIndex!,
                            child: Container(
                              width: 30, height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(child: Text('≡',
                                  style: TextStyle(color: WTheme.muted, fontSize: 18,
                                      fontWeight: FontWeight.w800))),
                            ),
                          ),
                        ],
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    // Row 2: Address tap
                    GestureDetector(
                      onTap: () => onShowAddress?.call(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('📍', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(order.addr1, style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w800, color: WTheme.navy,
                                fontSize: 16, letterSpacing: -0.3, height: 1.3)),
                            Text(order.addr2, style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600, color: WTheme.ink,
                                fontSize: 13, height: 1.35)),
                          ])),
                          Text('TAP', style: GoogleFonts.dmSans(
                              fontSize: 10, color: WTheme.muted,
                              fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Row 3: Patient + NEEDS COLLECTION
                    Row(children: [
                      const Text('👤', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(order.patient,
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600,
                              color: WTheme.muted, fontSize: 12))),
                      if (order.driverState == DriverState.collecting)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: WTheme.aqua,
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(context.tr('needsCollection'), style: GoogleFonts.dmSans(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    // Row 4: Action buttons
                    // CLIENT-REPORTED: removed LINK — there's no real
                    // payment link to send yet (see removed onCopyLink
                    // below), so showing the button just to toast "not
                    // ready" wasn't useful. Restore it once backend has
                    // an actual payment-link endpoint/format confirmed.
                    Row(children: [
                      _ActionBtn(emoji: '🗺', label: context.tr('map'),   color: WTheme.sky, onTap: onOpenMap),
                      const SizedBox(width: 6),
                      _ActionBtn(emoji: '📞', label: context.tr('callCap'),  color: WTheme.ok,  onTap: onCallCustomer),
                    ]),
                    const SizedBox(height: 10),
                    // Row 5: Pay chip + driver state + SLA
                    // CLIENT-REPORTED (2026-08-25): confirmed live —
                    // the longer "ONLINE · NOT PAID" text (added for the
                    // previous fix) pushed this row past the card's
                    // available width, clipping the SLA countdown at
                    // the edge ("00:28:49 lef[t]"). Root cause wasn't
                    // really the text length — this Row had no width
                    // constraint or wrapping at all, so ANY combination
                    // of chips wide enough would eventually overflow the
                    // same way. Switched to Wrap (matching the exact
                    // pattern the meta footer just below already uses)
                    // so chips move to a new line instead of clipping,
                    // regardless of how long any label ends up being.
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      PayChip(method: order.payMethod, paid: order.paid),
                      DriverStatePill(state: order.driverState, small: true,
                          pharmaciesPicked: order.pharmaciesPicked, pharmaciesTotal: order.pharmaciesTotal),
                      if (order.status != OrderStatus.done && order.status != OrderStatus.failed)
                        SlaCountdown(order: order, size: 's'),
                    ]),
                    const SizedBox(height: 10),
                    // Row 6: Meta footer
                    Container(
                      padding: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: WTheme.cloud, width: 1))),
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        _MetaChip('📅 ${_fmtDate(order.createdAt)}'),
                        Text('•', style: TextStyle(color: WTheme.cloud)),
                        _MetaChip('📦 ${order.items.length} item${order.items.length != 1 ? "s" : ""}'),
                        if (order.multiPharmacy) ...[
                          Text('•', style: TextStyle(color: WTheme.cloud)),
                          // CLIENT-REPORTED (2026-08-19): this showed
                          // "0 pharmacies" always — same class of bug
                          // already fixed once in Order Detail: it used
                          // order.pickups.length, a field confirmed to
                          // always be empty. order.pharmacies is the
                          // real, confirmed field. Also now tappable,
                          // opening the multi-pharmacy pickup screen for
                          // this specific order.
                          GestureDetector(
                            onTap: onOpenMultiPickup,
                            child: _MetaChip('🏥 ${order.pharmacies.length} pharmacies',
                                color: const Color(0xFF2A9BBC)),
                          ),
                        ],
                        if (order.deliveredAt != null) ...[
                          Text('•', style: TextStyle(color: WTheme.cloud)),
                          _MetaChip('✓ at ${_fmtTime(order.deliveredAt!)}', color: WTheme.ok),
                        ],
                      ]),
                    ),
                  ]),
                ),
              ),
              // Left accent stripe — inset slightly so it never overlaps the rounded corner curve
              if (!hasCall)
                Positioned(
                  left: 0,
                  top: cardRadius * 0.55,
                  bottom: cardRadius * 0.55,
                  child: Container(width: 5, color: edgeColor),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2,'0');
    final m = d.minute.toString().padLeft(2,'0');
    return '${months[d.month-1]} ${d.day}, $h:$m ${d.hour < 12 ? "AM" : "PM"}';
  }

  static String _fmtTime(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return '$h:${d.minute.toString().padLeft(2,'0')} ${d.hour < 12 ? "AM" : "PM"}';
  }
}

Widget _MetaChip(String text, {Color? color}) => Text(text,
    style: GoogleFonts.dmSans(fontSize: 11, color: color ?? WTheme.muted,
        fontWeight: FontWeight.w600));

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.emoji, required this.label,
    required this.color, this.onTap});
  final String emoji, label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.33), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 6,
              offset: const Offset(0, 2))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800,
              color: color, letterSpacing: 0.6)),
        ]),
      ),
    ),
  );
}

// ── Batch Group Header ─────────────────────────────────────────
class _BatchGroupHeader extends StatelessWidget {
  const _BatchGroupHeader({
    required this.batchOrderIds, required this.pharmacyName,
    required this.pharmacyAddr, required this.orders,
    required this.pickedUp, required this.onTap,
  });
  final List<String> batchOrderIds;
  final String pharmacyName, pharmacyAddr;
  final List<Order> orders;
  final Map<String, bool> pickedUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total       = batchOrderIds.length;
    final pickedCount = batchOrderIds.where((id) => pickedUp[id] == true).length;
    if (pickedCount == total) return const SizedBox.shrink();
    final batchOrders = batchOrderIds
        .map((id) => orders.where((o) => o.id == id).firstOrNull)
        .whereType<Order>().toList();
    final totalValue = batchOrders.fold(0.0, (s, o) => s + o.total);
    final pct = total == 0 ? 0.0 : pickedCount / total;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [WTheme.aqua, WTheme.sky]),
          boxShadow: [BoxShadow(color: WTheme.aqua.withOpacity(0.4),
              blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('📦 ACTIVE BATCH', style: GoogleFonts.dmSans(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            ),
            RichText(text: TextSpan(children: [
              TextSpan(text: totalValue.toStringAsFixed(3), style: GoogleFonts.dmSans(
                  color: Colors.white, fontSize: 17,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              TextSpan(text: ' KD', style: GoogleFonts.dmSans(
                  color: Colors.white.withOpacity(0.85), fontSize: 10,
                  fontWeight: FontWeight.w600)),
            ])),
          ]),
          const SizedBox(height: 10),
          Text('🏥 $pharmacyName', style: GoogleFonts.dmSans(
              color: Colors.white, fontSize: 17,
              fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text('$total orders to collect · $pharmacyAddr',
              style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.9), fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withOpacity(0.20),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            RichText(text: TextSpan(
              style: GoogleFonts.dmSans(color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700),
              children: [
                const TextSpan(text: '🛒 Collecting · '),
                TextSpan(text: '$pickedCount/$total',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: ' picked up'),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('Open pickup checklist →', style: GoogleFonts.dmSans(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Address Popup ──────────────────────────────────────────────
class _AddressPopup extends StatelessWidget {
  const _AddressPopup({required this.order, required this.onClose, required this.onOpenMap});
  final Order order;
  final VoidCallback onClose;
  final ValueChanged<Order> onOpenMap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: const Color(0xFF0F2438).withOpacity(0.55),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Colors.black26,
                    blurRadius: 40, offset: Offset(0, -10))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('📍 ADDRESS DETAILS', style: GoogleFonts.dmSans(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: WTheme.muted, letterSpacing: 0.6)),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(color: WTheme.cloud, shape: BoxShape.circle),
                      child: Center(child: Text('×', style: TextStyle(
                          color: WTheme.navy, fontWeight: FontWeight.w800, fontSize: 16))),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                _AddrRow(label: context.tr('areaBlock'), value: order.addr1,
                    color: WTheme.rose, fontSize: 18),
                const SizedBox(height: 12),
                _AddrRow(label: context.tr('streetHouse'), value: order.addr2,
                    color: WTheme.sky, fontSize: 16),
                if (order.landmark != null) ...[
                  const SizedBox(height: 12),
                  _AddrRow(label: context.tr('landmark'), value: order.landmark!,
                      color: WTheme.aqua, fontSize: 14),
                ],
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: WTheme.cloud,
                      borderRadius: BorderRadius.circular(12)),
                  child: RichText(text: TextSpan(children: [
                    TextSpan(text: '📞 ${order.phone}', style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 11)),
                    TextSpan(text: ' · ${order.distanceKm} km away · ⏱ ${order.etaMin} min',
                        style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
                  ])),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    onClose(); // close the address popup first
                    onOpenMap(order);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft,
                          end: Alignment.bottomRight, colors: [WTheme.sky, WTheme.navy]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: WTheme.sky.withOpacity(0.4),
                          blurRadius: 30, offset: const Offset(0, 12))],
                    ),
                    child: Center(child: Text('🗺 ${context.tr('openInMaps')}',
                        style: GoogleFonts.dmSans(color: Colors.white,
                            fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.4))),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddrRow extends StatelessWidget {
  const _AddrRow({required this.label, required this.value,
    required this.color, required this.fontSize});
  final String label, value;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: WTheme.blush,
      borderRadius: BorderRadius.circular(12),
      border: Border(left: BorderSide(color: color, width: 4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800,
          color: WTheme.muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.dmSans(fontSize: fontSize,
          fontWeight: FontWeight.w800, color: WTheme.navy, letterSpacing: -0.3)),
    ]),
  );
}