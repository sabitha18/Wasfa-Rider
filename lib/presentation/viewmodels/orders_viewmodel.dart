import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/network/api_client.dart';
import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';

class OrdersViewModel extends ChangeNotifier {
  final _repo = OrderRepository();
  Timer? _autoRefreshTimer;
  Timer? _batchPollTimer;
  // Tracks consecutive silent failures — see load()'s silent parameter.
  // A brief blip should stay quiet, but a SUSTAINED outage must not stay
  // silent forever: the driver needs to know the app has lost sync with
  // the server, not just keep working from stale data indefinitely.
  int _consecutiveSilentFailures = 0;
  // CLIENT-REPORTED (2026-08-22): tracks which multi-pharmacy orders
  // have already had a one-time detail-fetch backfill this session —
  // see load()'s use of this below. Prevents re-fetching the same
  // order's detail on every single 20s poll once it's already been done
  // once; _mergedPharmacies then correctly preserves that picked-up
  // data across subsequent list-only refreshes on its own.
  final Set<String> _detailBackfilledOrderIds = {};

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
  /// [silent] — CLIENT-REPORTED (2026-08-18): the red "Could not reach
  /// the server" error banner was showing up right after unlocking the
  /// phone. Root cause: the 20s auto-refresh timer calls this same
  /// method, and a brief network gap right after screen unlock (WiFi/
  /// radio reconnecting — completely normal, self-resolving in a second
  /// or two) was getting surfaced as a scary, user-facing error even
  /// though nothing was actually wrong. Silent background polls (the
  /// auto-refresh timer, and refreshes triggered by an incoming push
  /// notification) now swallow a transient failure quietly and just
  /// retry on the next cycle — only an EXPLICIT user action (tapping the
  /// refresh button, or the very first load on app start) still shows
  /// the error banner, since those are moments the user is actively
  /// waiting for feedback and genuinely needs to know if something failed.
  Future<void> load({bool silent = false}) async {
    isLoading = true;
    if (!silent) error = null;
    notifyListeners();
    try {
      // CLIENT-REPORTED: Orders screen's "All" tab was only ever showing
      // active+done merged client-side, never backend's own tab=all —
      // and backend's tab=all returns MORE orders than active+done
      // combined (confirmed live via Postman: 6 orders under tab=all vs.
      // only 3 covered between tab=active + tab=done — so some orders
      // exist that neither of those two individually returns, likely
      // ones with a status like "failed" that backend's own done-tab
      // query doesn't include). Fetch tab=all directly — it's backend's
      // own complete list, and activeOrder/activeOrders/doneOrders below
      // are already computed by filtering _orders locally, so nothing
      // else needs to change once _orders actually has everything in it.
      // CLIENT-REPORTED (2026-08-12): a status swipe (e.g. pending ->
      // collecting) was seen reverting back to "pending" after leaving
      // and returning to this order — either via Order Detail's own
      // refresh (see refreshOrder below) or, independently, via THIS
      // list refresh firing on its 20s auto-poll while the driver was
      // away on the map screen. Log any such reversal here too so
      // logcat shows which of the two paths (or both) actually produced
      // it, and what raw driver_state the list endpoint returned.
      final previous = {for (final o in _orders) o.id: o.driverState};
      final previousById = {for (final o in _orders) o.id: o};
      final fresh = await _repo.fetchOrders(tab: 'all');
      for (final o in fresh) {
        final before = previous[o.id];
        if (before != null && before != o.driverState) {
          debugPrint('[OrdersViewModel] load() driverState for ${o.id}: $before -> ${o.driverState}');
        }
      }
      // CLIENT-REPORTED (2026-08-19): merge each order's pharmacies
      // against whatever richer, detail-sourced data we already had for
      // it — see _mergedPharmacies's own doc for the full story. Without
      // this, item names and picked-up status fetched via Order Detail
      // or the multi-pickup screen would get silently wiped out by the
      // very next routine 20s poll, since the list endpoint has neither.
      _orders = fresh.map((o) {
        final prior = previousById[o.id];
        if (prior == null) return o;
        return o.copyWith(pharmacies: _mergedPharmacies(o.pharmacies, prior.pharmacies));
      }).toList();
      // CLIENT-REPORTED (2026-08-22): confirmed live — on a fresh app
      // launch (cold start), Home showed an ALREADY-picked-up pharmacy
      // as if it still needed collecting. Root cause: the list endpoint
      // (this fetch, above) has no picked_up/picked_at at all for any
      // pharmacy — only the detail endpoint does — and on a cold start
      // there's no "prior" cached order for _mergedPharmacies to
      // preserve accurate data from either, since the app just started.
      // Backfill: for any multi-pharmacy order not yet done/failed that
      // hasn't had its detail pulled this session, fetch it once in the
      // background so accurate per-pharmacy picked status is available
      // without the driver needing to happen to open Order Detail first.
      // One-time per order per session — _mergedPharmacies then
      // correctly preserves that picked-up data across every subsequent
      // list-only poll on its own, so this doesn't repeat every 20s.
      for (final o in _orders) {
        if (!o.multiPharmacy) continue;
        if (o.status == OrderStatus.done || o.status == OrderStatus.failed) continue;
        if (_detailBackfilledOrderIds.contains(o.id)) continue;
        _detailBackfilledOrderIds.add(o.id);
        refreshOrder(o.id, silent: true); // fire-and-forget — updates _orders + notifies once it completes
      }
      // CLIENT-REPORTED (2026-08-13): confirmed live via a real response
      // — backend's own "counts": {"active": 0, ...} showed genuinely
      // ZERO orders flagged driver_order_status=="active" at that
      // moment, even though there was clearly more work queued (stop 2
      // sitting at driver_order_status=="next"). This happens because
      // the only order ever flagged "active" had since failed — and
      // nothing (backend-side) promotes the next one to take its place.
      // Home's activeOrder getter requires status==active, so it went
      // completely blank despite real, undone work still in the list.
      // Self-heal here: if nothing is active but something is queued
      // (next/later), promote whichever has the lowest stopNumber — the
      // driver should always see what to do next, not an empty Home
      // screen just because backend hasn't explicitly flagged anyone yet.
      final hasActive = _orders.any((o) => o.status == OrderStatus.active);
      if (!hasActive) {
        const queuedStatuses = {OrderStatus.next, OrderStatus.later, OrderStatus.batchPending};
        final queued = _orders.where((o) => queuedStatuses.contains(o.status)).toList()
          ..sort((a, b) => a.stopNumber.compareTo(b.stopNumber));
        if (queued.isNotEmpty) {
          final promoteId = queued.first.id;
          _orders = _orders.map((o) => o.id == promoteId ? o.copyWith(status: OrderStatus.active) : o).toList();
          debugPrint('[OrdersViewModel] load() promoted $promoteId to active — backend had no order flagged active despite queued work');
        }
      }
      _pendingBatch = await _repo.fetchPendingBatch();
      _consecutiveSilentFailures = 0; // any success clears the streak
    } on ApiException catch (e) {
      if (silent) {
        _consecutiveSilentFailures++;
        // CLIENT-REPORTED (2026-08-18) follow-up: silencing every failure
        // unconditionally would let a genuinely SUSTAINED outage go
        // unnoticed forever — the driver would keep working from
        // increasingly stale data with zero indication anything's wrong.
        // A brief blip (screen unlock, momentary radio reconnect) means
        // 1-2 failures at most before the next poll succeeds; 3 in a row
        // is roughly a minute of no contact at all, past what a normal
        // reconnect blip looks like — treat that as a real problem worth
        // surfacing, not a transient one worth hiding.
        const maxSilentFailures = 3;
        if (_consecutiveSilentFailures >= maxSilentFailures) {
          debugPrint('[OrdersViewModel] load(silent) failed $_consecutiveSilentFailures times in a row — '
              'no longer treating this as a brief blip, surfacing it: ${e.message}');
          error = e.message;
        } else {
          debugPrint('[OrdersViewModel] load(silent) failed quietly ($_consecutiveSilentFailures/$maxSilentFailures — '
              'expected occasionally, e.g. right after screen unlock): ${e.message}');
        }
      } else {
        error = e.message;
        _consecutiveSilentFailures = 0;
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh({bool silent = false}) => load(silent: silent);

  /// Re-fetches a single order fresh from the backend (GET /orders/{code})
  /// and replaces it in the in-memory list. This endpoint existed in the
  /// repository but was never actually called anywhere — OrderDetailScreen
  /// only ever showed whatever was already loaded from the last /orders or
  /// /batch list poll (up to 20s stale), with no way to see this in
  /// logcat since no request was ever made for it. Called once when the
  /// detail screen opens.
  /// [silent] — CLIENT-REPORTED (2026-08-22): needed for load()'s
  /// proactive multi-pharmacy detail backfill (see there) — that's a
  /// background operation the driver never explicitly asked for, so a
  /// transient failure there shouldn't show the same red error banner
  /// reserved for actions they're actively waiting on, same reasoning
  /// as load()'s own silent parameter.
  Future<void> refreshOrder(String id, {bool silent = false}) async {
    final existing = findById(id);
    if (existing == null) return;
    Future<void> doFetch() async {
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
      // CLIENT-REPORTED (2026-08-12): after swiping a status forward
      // (e.g. pending -> collecting), opening Order Detail — which always
      // calls refreshOrder on init — was reverting it back to "pending".
      // Log old vs new here so a revert is unmistakable in logcat and
      // distinguishable from a legitimate change (e.g. the backend
      // correctly reporting the pharmacy already finished collecting).
      if (existing.driverState != fresh.driverState) {
        debugPrint('[OrdersViewModel] refreshOrder($id) driverState '
            '${existing.driverState} -> ${fresh.driverState} '
            '(see [fetchOrder] log above for the raw driver_state value that produced this)');
      }
      // CLIENT-REPORTED (2026-08-18): after visiting Order Detail and
      // returning to Home, tapping "Maps" started showing the customer's
      // location instead of the pharmacy's — even while still in the
      // heading-to-pharmacy phase. Confirmed via logcat: driver_state was
      // NOT the cause here (stayed "pending", unchanged) — the actual
      // cause is that this endpoint's pharmacies entries can come back
      // with lat/lng null even when the SAME pharmacy had real
      // coordinates moments earlier via the list endpoint. That's a
      // different failure mode than a fully-empty pharmacies array
      // (already handled below) — a present-but-coordless entry still
      // fails hasCoords, so the map falls back to the customer.
      // _mergedPharmacies handles both: an entirely missing/empty list
      // falls back to whatever we already had entirely, and a present
      // list backfills coordinates per-pharmacy (matched by seller id)
      // from the existing data whenever the fresh entry lacks them.
      final toApply = fresh.copyWith(pharmacies: _mergedPharmacies(fresh.pharmacies, existing.pharmacies));
      _updateOrder(id, toApply);
    }
    if (silent) {
      try {
        await doFetch();
      } catch (e) {
        debugPrint('[OrdersViewModel] refreshOrder($id, silent) failed quietly (expected occasionally): $e');
      }
    } else {
      await _guarded(doFetch);
      // Silent (data-wise) on failure even in the non-silent case — the
      // already-loaded (possibly stale) data just stays on screen rather
      // than blanking out over a transient network hiccup. The red
      // banner from _guarded still surfaces for THIS path though, since
      // this is the explicit, user-initiated refresh (e.g. Order Detail
      // opening) that the driver is actively waiting on.
    }
  }

  /// Merges a freshly-fetched pharmacies list against what we already
  /// had cached, backfilling anything the fresh fetch is missing rather
  /// than ever letting a refresh regress good data to worse.
  ///
  /// CLIENT-REPORTED (2026-08-19): the multi-pharmacy pickup screen
  /// showed items correctly right after opening (refreshOrder() had
  /// just fetched the real, detail-sourced item names), then went back
  /// to "0 items" moments later on its own. Root cause: this merge was
  /// only ever applied inside refreshOrder() — load() (the plain 20s
  /// auto-refresh, fetching from the LIST endpoint) did a wholesale
  /// _orders = fresh with no merge at all. The list endpoint has no
  /// nested item names or picked_up status at all, only a plain
  /// items_count number — so the very next routine poll after opening
  /// this screen would silently wipe out the richer detail data with
  /// the plainer list data, undoing what refreshOrder() had just fixed.
  /// Now handles three distinct fields that can regress this way: a
  /// fully empty pharmacies list, missing coordinates on an individual
  /// entry, and — the new part — missing item names and picked-up
  /// status, both of which only ever exist on the detail endpoint and
  /// must never be silently lost to a routine list refresh.
  List<Pharmacy> _mergedPharmacies(List<Pharmacy> fresh, List<Pharmacy> existing) {
    if (fresh.isEmpty) {
      if (existing.isNotEmpty) {
        debugPrint('[OrdersViewModel] pharmacies came back completely empty — keeping the existing ${existing.length} instead of wiping them');
      }
      return existing.isNotEmpty ? existing : fresh;
    }
    final existingBySeller = {for (final p in existing) if (p.sellerId != null) p.sellerId!: p};
    return fresh.map((p) {
      final prior = p.sellerId != null ? existingBySeller[p.sellerId] : null;
      if (prior == null) return p;
      final needsCoords = !p.hasCoords && prior.hasCoords;
      final needsItems = p.items.isEmpty && prior.items.isNotEmpty;
      final needsAddress = (p.address == null || p.address!.isEmpty) && (prior.address != null && prior.address!.isNotEmpty);
      final needsPickedUp = !p.pickedUp && prior.pickedUp;
      if (!needsCoords && !needsItems && !needsAddress && !needsPickedUp) return p;
      if (needsCoords) debugPrint('[OrdersViewModel] pharmacy seller ${p.sellerId} came back with no coordinates — backfilling from existing data');
      if (needsItems) debugPrint('[OrdersViewModel] pharmacy seller ${p.sellerId} came back with no item names — backfilling from existing data');
      if (needsPickedUp) debugPrint('[OrdersViewModel] pharmacy seller ${p.sellerId} came back not-picked-up but was already marked picked — keeping picked');
      return Pharmacy(
        sellerId: p.sellerId, name: p.name, phone: p.phone,
        address: needsAddress ? prior.address : p.address,
        lat: needsCoords ? prior.lat : p.lat,
        lng: needsCoords ? prior.lng : p.lng,
        itemsCount: p.itemsCount,
        items: needsItems ? prior.items : p.items,
        subtotal: needsItems ? prior.subtotal : p.subtotal,
        pickedUp: needsPickedUp ? true : p.pickedUp,
        pickedAt: needsPickedUp ? prior.pickedAt : p.pickedAt,
      );
    }).toList();
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
    _autoRefreshTimer = Timer.periodic(interval, (_) => refresh(silent: true));
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
      // CLIENT-REQUESTED: attach the driver's current lat/lng to every
      // status change. Fetched here directly (not via MapViewModel)
      // because a transition can be triggered from Order Detail too,
      // where the map isn't mounted and MapViewModel's own tracking may
      // not be running — Geolocator works regardless of which screen the
      // rider is on. Best-effort: a missing/slow fix must never block or
      // fail the status update itself, so any error just means no lat/lng
      // gets sent this time rather than the transition failing outright.
      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
        // NOTE: this project is pinned to geolocator 11.1.0, where
        // getCurrentPosition() still takes desiredAccuracy/timeLimit
        // directly rather than a LocationSettings object (that only
        // applies to getPositionStream() in this version — see
        // map_viewmodel.dart). Don't "modernize" this to
        // locationSettings without also bumping the geolocator version,
        // or it won't compile.
        pos ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        debugPrint('[OrdersViewModel] could not get position for status change (sending without lat/lng): $e');
      }
      final ok = await _guarded(() => _repo.updateStatus(
        o.co ?? o.id, statusStr, lat: pos?.latitude, lng: pos?.longitude,
      ));
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
  /// CLIENT-REPORTED (2026-08-19): rebuilt around order.pharmacies (the
  /// confirmed, real field) instead of order.pickups (confirmed elsewhere
  /// to always be empty — the entire multi-pickup screen was showing
  /// "0 pharmacies" because of it). [pharmacy] is the specific pharmacy
  /// being marked picked up.
  ///
  /// Follow-up (2026-08-19): silently swallowing a
  /// backend failure here was itself the wrong call, not just an
  /// interim safety measure — if this sync fails for ANY reason
  /// (the confirmed wrong-identifier bug just fixed, or anything
  /// unforeseen in the future), the app would show "picked up" while
  /// backend has zero record of it, with nothing ever telling the
  /// driver something didn't save. That's a real data-integrity risk
  /// for something that gates whether the order can even be delivered.
  /// Still updates local state optimistically first (so the checklist
  /// feels instant), but now returns whether the backend sync actually
  /// succeeded, so the caller can show an honest "not saved" warning on
  /// failure — same pattern already used for reorderActive's toast.
  Future<bool> markPharmacyPickedUp(String orderId, Pharmacy pharmacy) async {
    final o = findById(orderId);
    if (o == null) return false;
    final updatedPharmacies = o.pharmacies.map((p) {
      final isMatch = pharmacy.sellerId != null
          ? p.sellerId == pharmacy.sellerId
          : p.name == pharmacy.name;
      return isMatch ? p.copyWith(pickedUp: true, pickedAt: DateTime.now()) : p;
    }).toList();
    final allPicked = updatedPharmacies.every((p) => p.pickedUp);
    _updateOrder(orderId, o.copyWith(
      pharmacies: updatedPharmacies,
      driverState: allPicked ? DriverState.pickedUp : DriverState.collecting,
    ));
    final sellerId = pharmacy.sellerId;
    if (sellerId == null) {
      debugPrint('[OrdersViewModel] markPharmacyPickedUp: "${pharmacy.name}" has no seller_id — cannot sync to backend at all');
      return false;
    }
    try {
      // CLIENT-CONFIRMED LIVE (2026-08-19): this response hands back the
      // full, authoritative pharmacies array for the order — reconcile
      // local state against it rather than just trusting the optimistic
      // guess above, same pattern already used for reorderActive.
      final authoritativePharmacies = await _repo.pickupSeller(o.co ?? o.id, sellerId);
      if (authoritativePharmacies.isNotEmpty) {
        final current = findById(orderId);
        if (current != null) {
          final reconciled = _mergedPharmacies(authoritativePharmacies, current.pharmacies);
          final allPickedNow = reconciled.every((p) => p.pickedUp);
          _updateOrder(orderId, current.copyWith(
            pharmacies: reconciled,
            driverState: allPickedNow ? DriverState.pickedUp : DriverState.collecting,
          ));
        }
      }
      return true;
    } catch (e) {
      debugPrint('[OrdersViewModel] pickupSeller backend sync failed for "${pharmacy.name}" (seller $sellerId): $e');
      return false;
    }
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
  /// [newOrderedIds] is the FULL new sequence of active-pool order ids,
  /// first = top priority — exactly what the drag-and-drop UI already
  /// computes on every drag. SUPERSEDED (2026-08-18): this used to take
  /// just the one moved order + its target position, calling a per-order
  /// endpoint that needed a loop of calls for anything beyond a single
  /// swap (confirmed directly by the client: moving item #3 to #1 also
  /// displaces #1 and #2, needing their own follow-up calls to fix up).
  /// The new bulk endpoint takes the whole sequence in one call — no
  /// looping, and nothing to reconcile against afterward since the app
  /// is dictating the entire order itself, not asking backend to
  /// cascade-shift things around a single move.
  Future<bool> reorderActive(List<String> newOrderedIds) async {
    // Optimistic local update first, so the drag feels instant.
    //
    // Per Hashim's own explanation of why this feature was requested —
    // "the first order always show[s] the status on the homepage, so
    // that's why also [we need reordering]" — dragging to the top is
    // supposed to make that order the one that shows on Home. Both
    // stopNumber and `status` (the ONLY thing Home's activeOrder getter
    // looks at) go through the same _reorderAndRecomputeStatus (see
    // switchActive below too), so whichever order ends up first always
    // becomes Home's active card, not just a relabeled list entry.
    _reorderAndRecomputeStatus(newOrderedIds);

    // Deliberately NOT using the shared _guarded() helper here — that
    // also sets `error`, which triggers a separate, generic error
    // snackbar app-wide (see main.dart's _showOrdersError). This is a
    // low-stakes sync with its own tailored message already shown in
    // orders_screen.dart, so a second raw error on top would be noisy.
    try {
      final idToCo = {for (final o in _orders) o.id: o.co};
      final coIds = newOrderedIds.map((id) => idToCo[id]).whereType<String>().toList();
      if (coIds.length != newOrderedIds.length) {
        debugPrint('[OrdersViewModel] reorderActive: some orders had no co id — sending what resolved anyway');
      }
      await _repo.reorderActive(coIds);
      return true;
    } catch (e) {
      debugPrint('[OrdersViewModel] reorderActive sync failed: $e');
      return false;
    }
  }

  /// Triggered by tapping a map pin on Home. Now just a thin wrapper
  /// around the same shared logic reorderActive uses — see there for
  /// why these two needed to be unified.
  void switchActive(String newActiveId) {
    const activeStatuses = {OrderStatus.active, OrderStatus.next, OrderStatus.later, OrderStatus.batchPending};
    final activePool = _orders.where((o) => activeStatuses.contains(o.status)).toList();
    final orderedIds = [
      newActiveId,
      ...activePool.where((o) => o.id != newActiveId).map((o) => o.id),
    ];
    _reorderAndRecomputeStatus(orderedIds);
  }

  /// Shared by reorderActive (drag-to-reorder on the Orders screen) and
  /// switchActive (tapping a map pin on Home) — both need to do exactly
  /// the same thing: whichever order ends up first becomes the one that
  /// shows as the Home screen's active card (status=active), the rest
  /// queue up as next/later, and everyone's stopNumber reflects their
  /// new position. Also fixes the same data-loss bug reorderActive had:
  /// this used to manually reconstruct each Order field-by-field, which
  /// silently dropped pharmacies/mapLink/paymentLink/transactionId — all
  /// added to the model after this was originally written. copyWith
  /// carries every field through by construction, so it can't go stale
  /// like that again as more fields get added later.
  void _reorderAndRecomputeStatus(List<String> orderedIds) {
    const activeStatuses = {OrderStatus.active, OrderStatus.next, OrderStatus.later, OrderStatus.batchPending};
    final activePool = _orders.where((o) => activeStatuses.contains(o.status)).toList();
    final others = _orders.where((o) => !activeStatuses.contains(o.status)).toList();

    final byId = {for (final o in activePool) o.id: o};
    // Defensive: any active-pool order NOT mentioned in orderedIds
    // (shouldn't normally happen) still gets appended at the end rather
    // than silently dropped.
    final reordered = <Order>[
      for (final id in orderedIds) if (byId.containsKey(id)) byId[id]!,
      for (final o in activePool) if (!orderedIds.contains(o.id)) o,
    ];

    final updatedPool = <Order>[];
    for (int i = 0; i < reordered.length; i++) {
      final newStatus = i == 0 ? OrderStatus.active : (i == 1 ? OrderStatus.next : OrderStatus.later);
      updatedPool.add(reordered[i].copyWith(stopNumber: i + 1, status: newStatus));
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
