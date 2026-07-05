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

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    required this.onTabChange,
    required this.onOpenOrder,
    required this.onOpenBatchPickup,
    required this.onCallNow,
  });
  final ValueChanged<String> onTabChange;
  final ValueChanged<String> onOpenOrder;
  final VoidCallback onOpenBatchPickup;
  final ValueChanged<String> onCallNow;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _filter = 'active';
  Order? _addrOrder;

  // ── Date filter state ──
  String _dateFilter = 'all'; // 'today', 'yesterday', 'week', 'all', 'custom'
  DateTime? _customDate;

  static const _activeStatuses = {
    OrderStatus.active, OrderStatus.next, OrderStatus.later, OrderStatus.batchPending
  };

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

  List<Order> _filtered(List<Order> orders) {
    final byStatus = switch (_filter) {
      'active' => orders.where((o) => _activeStatuses.contains(o.status)),
      'done'   => orders.where((o) => o.status == OrderStatus.done || o.status == OrderStatus.failed),
      _        => orders,
    };
    return byStatus.where(_matchesDate).toList();
  }

  int _count(List<Order> orders, String f) {
    final byStatus = switch (f) {
      'active' => orders.where((o) => _activeStatuses.contains(o.status)),
      'done'   => orders.where((o) => o.status == OrderStatus.done || o.status == OrderStatus.failed),
      _        => orders,
    };
    return byStatus.where(_matchesDate).length;
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
    final orders   = vm.orders;
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
          orders: orders,
          pickedUp: vm.batchPickedUp,
          onTap: widget.onOpenBatchPickup,
        ),
      _FilterTabs(filter: _filter, orders: orders, count: _count,
          onChanged: (f) => setState(() => _filter = f)),
      const SizedBox(height: 10),
      _DateFilterRow(
        dateFilter: _dateFilter,
        customDate: _customDate,
        onChanged: (f) => setState(() {
          _dateFilter = f;
          _customDate = null;
        }),
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
          }
        },
        onClearCustom: () => setState(() {
          _customDate = null;
          _dateFilter = 'all';
        }),
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
    final headers = _headers(orders, vm);
    return ReorderableListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      buildDefaultDragHandles: false,
      onReorder: (oldIdx, newIdx) {
        final hLen = headers.length;
        final from = oldIdx - hLen;
        var to = newIdx - hLen;
        if (from < 0 || from >= filtered.length) return;
        if (to > from) to -= 1;
        to = to.clamp(0, filtered.length - 1);
        final ids = filtered.map((o) => o.id).toList();
        ids.insert(to, ids.removeAt(from));
        vm.reorderActive(ids);
        showWToast(context, '🔢 Order sequence updated — next stop is now #1');
      },
      children: [
        for (int i = 0; i < headers.length; i++)
          _NonDraggableItem(key: ValueKey('h$i'), child: headers[i]),
        ...filtered.asMap().entries.map((e) {
          final idx = e.key + headers.length;
          final o   = e.value;
          // Pass dragIndex so the card renders the ≡ handle inside itself
          return _buildCardWidget(o, vm, dragIndex: idx);
        }),
        if (filtered.isEmpty)
          _NonDraggableItem(key: const ValueKey('empty'), child: _emptyState()),
      ],
    );
  }

  // ── Normal scroll list (done/all tab) ─────────────────────────
  Widget _buildNormalList(List<Order> filtered, OrdersViewModel vm, List<Order> orders) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      children: [
        ..._headers(orders, vm),
        ...filtered.map((o) => _buildCardWidget(o, vm)),
        if (filtered.isEmpty) _emptyState(),
      ],
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
    onCopyLink: () {
      Clipboard.setData(ClipboardData(text: 'https://wasfa.kw/pay/${o.id}'));
      showWToast(context, '🔗 Payment link copied · ${o.id}');
    },
    onOpenMap: () async {
      final q = Uri.encodeComponent('${o.addr1}, ${o.addr2}, Kuwait');
      final url = 'https://www.google.com/maps/search/?api=1&query=$q';
      if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
    },
    onCallCustomer: () async {
      final url = 'tel:${o.phone.replaceAll(RegExp(r'\s'), '')}';
      if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
    },
    onShowAddress: () => setState(() => _addrOrder = o),
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      const Text('📋', style: TextStyle(fontSize: 32)),
      const SizedBox(height: 10),
      Text('No orders here yet',
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
  const _FilterTabs({required this.filter, required this.orders,
    required this.count, required this.onChanged});
  final String filter;
  final List<Order> orders;
  final int Function(List<Order>, String) count;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      for (final f in [('active', 'Active'), ('done', 'Done'), ('all', 'All')])
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
            child: Center(child: Text('${f.$2} (${count(orders, f.$1)})',
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
    const options = [
      ('today', 'Today'),
      ('yesterday', 'Yesterday'),
      ('week', 'This Week'),
      ('all', 'All'),
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
    this.onCopyLink,
    this.onOpenMap,
    this.onCallCustomer,
    this.onShowAddress,
  });
  final Order order;
  final VoidCallback onTap;
  final Color edgeColor;
  final int? dragIndex;          // non-null = show ≡ drag handle
  final VoidCallback? onCallNow, onCancelEscalation, onCopyLink, onOpenMap, onCallCustomer, onShowAddress;

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
                          child: Text('NEEDS COLLECTION', style: GoogleFonts.dmSans(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    // Row 4: Action buttons
                    Row(children: [
                      _ActionBtn(emoji: '🔗', label: 'LINK',  color: WTheme.ok,  onTap: onCopyLink),
                      const SizedBox(width: 6),
                      _ActionBtn(emoji: '🗺', label: 'MAP',   color: WTheme.sky, onTap: onOpenMap),
                      const SizedBox(width: 6),
                      _ActionBtn(emoji: '📞', label: 'CALL',  color: WTheme.ok,  onTap: onCallCustomer),
                    ]),
                    const SizedBox(height: 10),
                    // Row 5: Pay chip + driver state + SLA
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        PayChip(method: order.payMethod, paid: order.paid),
                        const SizedBox(width: 6),
                        DriverStatePill(state: order.driverState, small: true),
                      ]),
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
                          _MetaChip('🏥 ${order.pickups.length} pharmacies',
                              color: const Color(0xFF2A9BBC)),
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
  const _AddressPopup({required this.order, required this.onClose});
  final Order order;
  final VoidCallback onClose;

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
                _AddrRow(label: 'AREA · BLOCK', value: order.addr1,
                    color: WTheme.rose, fontSize: 18),
                const SizedBox(height: 12),
                _AddrRow(label: 'STREET · HOUSE / APT', value: order.addr2,
                    color: WTheme.sky, fontSize: 16),
                if (order.landmark != null) ...[
                  const SizedBox(height: 12),
                  _AddrRow(label: 'LANDMARK', value: order.landmark!,
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
                  onTap: () async {
                    final q = Uri.encodeComponent('${order.addr1}, ${order.addr2}, Kuwait');
                    final url = 'https://www.google.com/maps/search/?api=1&query=$q';
                    if (await canLaunchUrl(Uri.parse(url))) launchUrl(Uri.parse(url));
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
                    child: Center(child: Text('🗺 OPEN IN MAPS',
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