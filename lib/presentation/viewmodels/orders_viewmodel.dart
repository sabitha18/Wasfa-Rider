import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';

class OrdersViewModel extends ChangeNotifier {
  final _repo = OrderRepository();
  Timer? _autoRefreshTimer;
  Timer? _batchPollTimer;

  List<Order> _orders = [];
  Batch? _pendingBatch;
  List<String> _batchOrderIds = [];
  Map<String, bool> _batchPickedUp = {};
  String? _batchPharmacyName;
  String? _batchPharmacyAddr;

  bool isLoading = false;
  String? error;

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

  /// Call from a FutureBuilder / initState instead of the old sync init().
  /// Loads active orders + any pending batch offer from the real API.
  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      // Previously only ever fetched tab=active — meaning Done/All order
      // history was NEVER actually loaded from the backend. It only ever
      // showed orders that happened to get marked delivered during THIS
      // session (a local in-memory status change), and reset to
      // completely empty on every fresh app start since nothing re-fetched
      // historical completed orders. Now fetches both and merges them.
      final results = await Future.wait([
        _repo.fetchOrders(tab: 'active'),
        _repo.fetchOrders(tab: 'done'),
      ]);
      // Dedupe by id in case an order transitions status mid-fetch and
      // briefly appears in both lists — done wins since it's merged last.
      final combined = <String, Order>{};
      for (final o in results[0]) combined[o.id] = o;
      for (final o in results[1]) combined[o.id] = o;
      _orders = combined.values.toList();
      _pendingBatch = await _repo.fetchPendingBatch();
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Re-fetches a single order fresh from the backend (GET /orders/{code})
  /// and replaces it in the in-memory list. This endpoint existed in the
  /// repository but was never actually called anywhere — OrderDetailScreen
  /// only ever showed whatever was already loaded from the last /orders or
  /// /batch list poll (up to 20s stale), with no way to see this in
  /// logcat since no request was ever made for it. Called once when the
  /// detail screen opens.
  Future<void> refreshOrder(String id) async {
    final existing = findById(id);
    if (existing == null) return;
    await _guarded(() async {
      final fresh = await _repo.fetchOrder(existing.co ?? existing.id);
      // Guard against ever repeating the corruption bug found live: a
      // response-shape mismatch once produced an Order with a blank id,
      // which silently overwrote this order's correct entry (replacement
      // is by array position, not by matching id). Refuse to apply a
      // fetch that came back malformed like that, regardless of cause.
      if (fresh.id.isEmpty) {
        debugPrint('[OrdersViewModel] refreshOrder($id) got a malformed order back (blank id) — ignoring, keeping existing cached data');
        return;
      }
      _updateOrder(id, fresh);
    });
    // Silent on failure — the already-loaded (possibly stale) data just
    // stays on screen rather than blanking out over a transient network hiccup.
  }

  /// Driver accepted a new-batch offer (see BatchIncomingScreen). Reloads
  /// the full order list afterward — the batch's orders should now come
  /// back as real active/next/later orders instead of OrderStatus.batchPending.
  Future<bool> acceptPendingBatch() async {
    final batch = _pendingBatch;
    if (batch?.id == null) return false;
    final ok = await _guarded(() => _repo.acceptBatch(batch!.id!));
    if (ok) await load();
    return ok;
  }

  /// Driver declined a new-batch offer. Clears it locally right away
  /// rather than waiting for the next poll to notice it's gone.
  Future<bool> rejectPendingBatch() async {
    final batch = _pendingBatch;
    if (batch?.id == null) return false;
    final ok = await _guarded(() => _repo.rejectBatch(batch!.id!));
    if (ok) {
      _pendingBatch = null;
      notifyListeners();
    }
    return ok;
  }

  /// Silently re-polls /orders every [interval] — a stopgap for "the
  /// driver should see a newly-assigned order without manually pulling
  /// to refresh". A real push (FCM new-order notification -> trigger
  /// refresh immediately) should replace/supplement this once that's
  /// wired up; this polling is what covers the gap until then, and is
  /// also a reasonable permanent fallback in case a push is ever missed.
  /// Safe to call repeatedly — restarts the timer rather than stacking.
  void startAutoRefresh({Duration interval = const Duration(seconds: 20)}) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(interval, (_) => refresh());
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// Batch offers have a 15-SECOND countdown (see BatchIncomingScreen), but
  /// the only thing checking for them was the general 20s order refresh —
  /// meaning a batch could easily expire before the app ever noticed it,
  /// even with the app open. This polls the lightweight /batch-check
  /// endpoint on its own, much tighter interval, independent of the
  /// general order refresh, specifically so this has a real chance of
  /// catching an offer within its own lifetime.
  void startBatchPolling({Duration interval = const Duration(seconds: 5)}) {
    _batchPollTimer?.cancel();
    _batchPollTimer = Timer.periodic(interval, (_) => _pollForBatch());
  }

  void stopBatchPolling() {
    _batchPollTimer?.cancel();
    _batchPollTimer = null;
  }

  Future<void> _pollForBatch() async {
    try {
      final batch = await _repo.fetchPendingBatch();
      if (batch?.id != _pendingBatch?.id) {
        _pendingBatch = batch;
        notifyListeners();
      }
    } catch (_) {
      // Silent — a transient failure on this lightweight poll shouldn't
      // disrupt anything else on screen; the next tick will just try again.
    }
  }

  @override
  void dispose() {
    stopAutoRefresh();
    stopBatchPolling();
    super.dispose();
  }

  Order? findById(String id) => _orders.firstWhereOrNull((o) => o.id == id);

  void _updateOrder(String id, Order updated) {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx >= 0) {
      _orders[idx] = updated;
      notifyListeners();
    }
  }

  /// CONFIRMED v2 — generic status update, now backed by a real endpoint.
  /// Valid [status] values: 'collecting' | 'picked_up' | 'on_the_way'.
  /// Kept the old name for existing call sites; it's no longer local-only.
  Future<void> transitionDriverState(String orderId, DriverState newState) async {
    final o = findById(orderId);
    if (o == null) return;
    final statusStr = _statusStringFor(newState);
    if (statusStr != null) {
      final ok = await _guarded(() => _repo.updateStatus(o.co ?? o.id, statusStr));
      if (!ok) return;
    }
    _updateOrder(orderId, o.copyWith(driverState: newState));
  }

  /// Maps a DriverState to the string /orders/{co}/status expects.
  /// Returns null for states with no matching backend value (delivered/
  /// failed/pending go through their own dedicated endpoints instead).
  String? _statusStringFor(DriverState s) {
    switch (s) {
      case DriverState.collecting: return 'collecting';
      case DriverState.pickedUp: return 'picked_up';
      case DriverState.onMyWay: return 'on_the_way';
      default: return null;
    }
  }

  Future<bool> _guarded(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  // ── Driver-state machine — now backed by real endpoints ────────
  Future<void> arriveAtPatient(String orderId) async {
    final o = findById(orderId);
    if (o == null) return;
    final ok = await _guarded(() => _repo.arrive(o.co ?? o.id));
    if (!ok) return;
    _updateOrder(orderId, o.copyWith(
      driverState: DriverState.onMyWay,
      status: OrderStatus.active,
    ));
  }

  /// [payMethod] MUST be one of the CONFIRMED v2 values 'cash'|'knet'|'paid'
  /// — use `OrderRepository.methodForOrder(order)` to compute this
  /// correctly (it is NOT the same as the app's PayMethod enum values).
  /// [podPhotoPath] is now REQUIRED — CONFIRMED the backend's /finish
  /// endpoint needs a real proof-of-delivery photo. [payMethod] is still
  /// sent too (kept optional server-side per the same endpoint's ambiguity
  /// — see OrderRepository.finish).
  Future<void> markDelivered(
      String orderId, {
        required String podPhotoPath,
        String? payMethod,
        String? given,
        String? signatureBase64,
      }) async {
    final o = findById(orderId);
    if (o == null) return;
    final ok = await _guarded(() => _repo.finish(
      o.co ?? o.id,
      podPhotoPath: podPhotoPath,
      method: payMethod,
      given: given,
      signatureBase64: signatureBase64,
    ));
    if (!ok) return;
    _updateOrder(orderId, o.copyWith(
      status: OrderStatus.done,
      driverState: DriverState.delivered,
      deliveredAt: DateTime.now(),
    ));
    final next = _orders.firstWhereOrNull((x) => x.status == OrderStatus.next);
    if (next != null) {
      _updateOrder(next.id, next.copyWith(status: OrderStatus.active));
    }
  }

  Future<void> markFailed(String orderId, String reason) async {
    final o = findById(orderId);
    if (o == null) return;
    final ok = await _guarded(() => _repo.fail(o.co ?? o.id, reason: reason));
    if (!ok) return;
    _updateOrder(orderId, o.copyWith(
      status: OrderStatus.failed,
      driverState: DriverState.failed,
      failureReason: reason,
    ));
  }

  // ── Batch handling — now backed by real endpoints ──────────────
  Future<void> acceptBatch(Batch batch, String batchId) async {
    final ok = await _guarded(() => _repo.acceptBatch(batchId));
    if (!ok) return;
    _batchOrderIds = batch.orders.map((o) => o.id).toList();
    _batchPickedUp = {};
    _batchPharmacyName = batch.pharmacyName;
    _batchPharmacyAddr = batch.pharmacyAddr;
    _orders.addAll(batch.orders);
    _pendingBatch = null;
    notifyListeners();
  }

  Future<void> rejectBatch(String batchId) async {
    final ok = await _guarded(() => _repo.rejectBatch(batchId));
    if (!ok) return;
    _pendingBatch = null;
    notifyListeners();
  }

  /// CONFIRMED v3 — pickup is genuinely pharmacy-based now, not order-based
  /// (the old "legacy" combined_order_id toggle is gone entirely). Since
  /// the current BatchPickupScreen models a batch as ONE pharmacy with
  /// multiple orders, tapping "Pick" on any order in that batch now calls
  /// [togglePharmacyCollected] with the batch's pharmacy NAME — marking the
  /// whole pharmacy (and so, in this single-pharmacy-batch model, the
  /// whole batch) collected, while still updating just the tapped order's
  /// local UI state for the per-row checkmark.
  Future<void> markBatchOrderPickedUp(String orderId) async {
    final o = findById(orderId);
    if (_batchPharmacyName == null) return;
    final ok = await _guarded(() => _repo.togglePharmacyCollected(_batchPharmacyName!));
    if (!ok) return;
    _batchPickedUp[orderId] = true;
    if (o != null) {
      _updateOrder(orderId, o.copyWith(driverState: DriverState.pickedUp));
    }
    final allPicked = _batchOrderIds.every((id) => _batchPickedUp[id] == true);
    if (allPicked) {
      final first = _batchOrderIds.isNotEmpty ? findById(_batchOrderIds.first) : null;
      if (first != null) {
        _updateOrder(first.id, first.copyWith(status: OrderStatus.active));
      }
    }
    notifyListeners();
  }

  // ── Multi-pharmacy pickup (single order spanning multiple pharmacies) ──
  /// CONFIRMED v3 — [phId] must be the pharmacy's NAME string (e.g.
  /// "Royal Pharmacy"), matching the `seller` concept used everywhere else
  /// in the pickup endpoints — NOT a numeric id like earlier guesses
  /// assumed. If `PharmacyPickup.phId` isn't already populated with the
  /// real pharmacy name from the backend, use `PharmacyPickup.name` when
  /// calling this instead.
  Future<void> markPharmacyPickedUp(String orderId, String phId) async {
    final o = findById(orderId);
    if (o == null) return;
    final ok = await _guarded(() => _repo.pickupSeller(o.co ?? o.id, phId));
    if (!ok) return;
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

  // ── Call requests / escalation ──────────────────────────────────
  // NOTE: no matching endpoints found in the Postman collection for
  // call-request accept/reject or escalation. These still only mutate
  // local state — ask backend if/where these should post, or whether
  // this feature is handled entirely differently server-side (e.g. via
  // push notifications and no rider-initiated call).
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

  // ── Reorder / switch active ─────────────────────────────────────
  // NOTE: no reorder endpoint found in the Postman collection either.
  // These stay local-only for now — ask backend whether stop order is
  // meant to be persisted server-side or is a rider-app-only concept.
  void reorderActive(List<String> newOrderedIds) {
    for (int i = 0; i < newOrderedIds.length; i++) {
      final idx = _orders.indexWhere((x) => x.id == newOrderedIds[i]);
      if (idx < 0) continue;
      final o = _orders[idx];
      _orders[idx] = Order(
        id: o.id, co: o.co, stopNumber: i + 1, patient: o.patient, phone: o.phone,
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
    }
    notifyListeners();
  }

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
        id: o.id, co: o.co, stopNumber: i + 1, patient: o.patient, phone: o.phone,
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
