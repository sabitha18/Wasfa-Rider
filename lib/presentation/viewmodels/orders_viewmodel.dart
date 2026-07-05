import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';

class OrdersViewModel extends ChangeNotifier {
  List<Order> _orders = [];
  Batch? _pendingBatch;
  List<String> _batchOrderIds = [];
  Map<String, bool> _batchPickedUp = {};
  String? _batchPharmacyName;
  String? _batchPharmacyAddr;

  List<Order> get orders => _orders;
  Batch? get pendingBatch => _pendingBatch;
  List<String> get batchOrderIds => _batchOrderIds;
  Map<String, bool> get batchPickedUp => _batchPickedUp;
  String? get batchPharmacyName => _batchPharmacyName;
  String? get batchPharmacyAddr => _batchPharmacyAddr;

  Order? get activeOrder => _orders.firstWhereOrNull(
        (o) => o.status == OrderStatus.active,
  );

  List<Order> get activeOrders => _orders.where((o) =>
      [OrderStatus.active, OrderStatus.next, OrderStatus.later, OrderStatus.batchPending]
          .contains(o.status)).toList();

  List<Order> get doneOrders => _orders.where((o) =>
  o.status == OrderStatus.done || o.status == OrderStatus.failed).toList();

  void init() {
    _orders = OrderRepository.seedOrders();
    _pendingBatch = OrderRepository.seedBatch();
    notifyListeners();
  }

  Order? findById(String id) => _orders.firstWhereOrNull((o) => o.id == id);

  void _updateOrder(String id, Order updated) {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx >= 0) {
      _orders[idx] = updated;
      notifyListeners();
    }
  }

  // ── Driver-state machine ──────────────────────────────────────
  void transitionDriverState(String orderId, DriverState newState) {
    final o = findById(orderId);
    if (o == null) return;
    _updateOrder(orderId, o.copyWith(driverState: newState));
  }

  void arriveAtPatient(String orderId) {
    final o = findById(orderId);
    if (o == null) return;
    _updateOrder(orderId, o.copyWith(
      driverState: DriverState.onMyWay,
      status: OrderStatus.active,
    ));
  }

  void markDelivered(String orderId) {
    final o = findById(orderId);
    if (o == null) return;
    _updateOrder(orderId, o.copyWith(
      status: OrderStatus.done,
      driverState: DriverState.delivered,
      deliveredAt: DateTime.now(),
    ));
    // Promote next → active
    final next = _orders.firstWhereOrNull((x) => x.status == OrderStatus.next);
    if (next != null) {
      _updateOrder(next.id, next.copyWith(status: OrderStatus.active));
    }
  }

  void markFailed(String orderId, String reason) {
    final o = findById(orderId);
    if (o == null) return;
    _updateOrder(orderId, o.copyWith(
      status: OrderStatus.failed,
      driverState: DriverState.failed,
      failureReason: reason,
    ));
  }

  // ── Batch handling ────────────────────────────────────────────
  void acceptBatch(Batch batch) {
    _batchOrderIds = batch.orders.map((o) => o.id).toList();
    _batchPickedUp = {};
    _batchPharmacyName = batch.pharmacyName;
    _batchPharmacyAddr = batch.pharmacyAddr;
    _orders.addAll(batch.orders);
    _pendingBatch = null;
    notifyListeners();
  }

  void rejectBatch() {
    _pendingBatch = null;
    notifyListeners();
  }

  void markBatchOrderPickedUp(String orderId) {
    _batchPickedUp[orderId] = true;
    final o = findById(orderId);
    if (o != null) {
      _updateOrder(orderId, o.copyWith(driverState: DriverState.pickedUp));
    }
    // If all picked up, activate first in sequence
    final allPicked = _batchOrderIds.every((id) => _batchPickedUp[id] == true);
    if (allPicked) {
      final first = _batchOrderIds.isNotEmpty ? findById(_batchOrderIds.first) : null;
      if (first != null) {
        _updateOrder(first.id, first.copyWith(status: OrderStatus.active));
      }
    }
    notifyListeners();
  }

  // ── Multi-pharmacy ────────────────────────────────────────────
  void markPharmacyPickedUp(String orderId, String phId) {
    final o = findById(orderId);
    if (o == null) return;
    final updated = o.pickups.map((p) {
      if (p.phId == phId) return p.copyWith(picked: true);
      return p;
    }).toList();
    final allPicked = updated.every((p) => p.picked);
    _updateOrder(orderId, o.copyWith(
      pickups: updated,
      driverState: allPicked ? DriverState.pickedUp : DriverState.collecting,
    ));
  }

  // ── Call requests ─────────────────────────────────────────────
  void acceptCallRequest(String orderId) {
    final o = findById(orderId);
    if (o?.callRequest == null) return;
    o!.callRequest!.status = 'accepted';
    _updateOrder(orderId, o);
  }

  void rejectCallRequest(String orderId, String reason, String note) {
    final o = findById(orderId);
    if (o?.callRequest == null) return;
    o!.callRequest!.status = 'rejected';
    o.callRequest!.rejectionReason = reason;
    o.callRequest!.rejectionNote = note;
    _updateOrder(orderId, o);
  }

  void requestEscalation(String orderId) {
    final o = findById(orderId);
    if (o == null) return;
    _updateOrder(orderId, o.copyWith(
      callEscalation: CallEscalation(at: DateTime.now()),
    ));
  }

  void cancelEscalation(String orderId) {
    final o = findById(orderId);
    if (o == null) return;
    o.callEscalation?.status = 'resolved';
    _updateOrder(orderId, o);
  }

  // ── Reorder ───────────────────────────────────────────────────
  void reorderActive(List<String> newOrderedIds) {
    // Update stopNumbers
    for (int i = 0; i < newOrderedIds.length; i++) {
      final o = findById(newOrderedIds[i]);
      if (o == null) continue;
      // We create a fresh copy with new stopNumber via a simple reassignment
      final idx = _orders.indexWhere((x) => x.id == newOrderedIds[i]);
      if (idx >= 0) {
        // Minimal copy with updated stopNumber
        final updated = Order(
          id: o.id, stopNumber: i + 1, patient: o.patient, phone: o.phone,
          addr1: o.addr1, addr2: o.addr2, landmark: o.landmark,
          customerNote: o.customerNote, items: o.items, total: o.total,
          paid: o.paid, payMethod: o.payMethod, discount: o.discount,
          deliveryFee: o.deliveryFee, status: o.status,
          driverState: o.driverState, distanceKm: o.distanceKm,
          etaMin: o.etaMin, pinPos: o.pinPos, multiPharmacy: o.multiPharmacy,
          pickups: o.pickups, deliveredAt: o.deliveredAt,
          failureReason: o.failureReason, callRequest: o.callRequest,
          callEscalation: o.callEscalation, createdAt: o.createdAt,
          slaMinutes: o.slaMinutes,
        );
        _orders[idx] = updated;
      }
    }
    notifyListeners();
  }

  // ── Switch active (tap a pin → that order becomes stop #1) ─────
  // Mirrors the HTML's onSwitchActive exactly: reorders the active pool
  // (active/next/later/batchPending) so the tapped order goes first,
  // then reassigns stopNumber + status (1st=active, 2nd=next, rest=later).
  // Note: stopNumber is final on Order, so we rebuild each affected order
  // rather than mutating in place; status alone is mutable and set directly.
  void switchActive(String newActiveId) {
    const activeStatuses = {OrderStatus.active, OrderStatus.next, OrderStatus.later, OrderStatus.batchPending};
    final activePool = _orders.where((o) => activeStatuses.contains(o.status)).toList();
    final others = _orders.where((o) => !activeStatuses.contains(o.status)).toList();

    final tapped = activePool.where((o) => o.id == newActiveId).toList();
    final rest = activePool.where((o) => o.id != newActiveId).toList();
    final reordered = [...tapped, ...rest];

    final updatedPool = <Order>[];
    for (int i = 0; i < reordered.length; i++) {
      final o = reordered[i];
      final newStatus = i == 0 ? OrderStatus.active : (i == 1 ? OrderStatus.next : OrderStatus.later);
      updatedPool.add(Order(
        id: o.id, stopNumber: i + 1, patient: o.patient, phone: o.phone,
        addr1: o.addr1, addr2: o.addr2, landmark: o.landmark,
        customerNote: o.customerNote, items: o.items, total: o.total,
        paid: o.paid, payMethod: o.payMethod, discount: o.discount,
        deliveryFee: o.deliveryFee, status: newStatus,
        driverState: o.driverState, distanceKm: o.distanceKm,
        etaMin: o.etaMin, pinPos: o.pinPos, multiPharmacy: o.multiPharmacy,
        pickups: o.pickups, deliveredAt: o.deliveredAt,
        failureReason: o.failureReason, callRequest: o.callRequest,
        callEscalation: o.callEscalation, createdAt: o.createdAt,
        slaMinutes: o.slaMinutes,
      ));
    }

    _orders
      ..clear()
      ..addAll([...updatedPool, ...others]);
    notifyListeners();
  }
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}
