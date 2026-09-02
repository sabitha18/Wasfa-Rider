import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../models/models.dart';

/// Replaces the old seed-data OrderRepository with real API calls.
/// `id` on Order is the order `code` (e.g. "APM10061"). Some routes
/// (arrive/pickup/finish/fail/building-photos/geocode) use `{co}`, the
/// numeric internal id (Order.co, from co_id) — CONFIRMED genuinely
/// different from `code` via extensive real testing throughout this
/// project (e.g. code="APM36104" vs co_id=26341). Callers consistently
/// pass `order.co ?? order.id` for these routes.
class OrderRepository {
  final _api = ApiClient.instance;

  /// CLIENT-REQUESTED (2026-08-31): tab labels ("Done (50)") were showing
  /// a client-side count over whatever's currently in the in-memory list
  /// — misleading once that list is only a partial/paginated slice, since
  /// the label looked like a real total but was actually just "however
  /// many happen to be loaded right now". Backend's own response already
  /// includes an authoritative "counts" object with the REAL totals
  /// (e.g. {"active":0,"done":4183,"all":4241}) — now returned alongside
  /// the parsed order list so the UI can show the real number.
  ///
  /// [dateFrom]/[dateTo] — CLIENT-ASKED (2026-08-31): requested from
  /// Soumya as `YYYY-MM-DD`, filtering by created_at, applied BEFORE
  /// pagination on her end (not after — see the actual ask for why that
  /// distinction matters). NOT YET CONFIRMED live as of this writing —
  /// sent whenever a date filter other than "All" is active, but
  /// written defensively: an unrecognized query param is typically just
  /// ignored by a server that hasn't implemented it yet, so this should
  /// be safe to send regardless. The existing client-side date filter
  /// in orders_screen.dart stays in place either way, as a safety net —
  /// this isn't replacing that, just supplementing it once backend
  /// support is confirmed.
  Future<({List<Order> orders, Map<String, int> counts})> fetchOrders({
    String tab = 'active',
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, dynamic>{'tab': tab};
    if (dateFrom != null) query['date_from'] = dateFrom;
    if (dateTo != null) query['date_to'] = dateTo;
    final res = await _api.get(ApiConfig.orders, query: query);
    // CONFIRMED v2: top-level key is "list", not "data"/"orders".
    final list = (res['list'] ?? res['data'] ?? res['orders'] ?? const []) as List;
    // TEMP DEBUG (missing-order investigation): log exactly what codes came
    // back raw from the server for this tab, before any parsing/filtering,
    // so we can tell "backend never sent it" apart from "we dropped it
    // during parsing" for a specific order like APM85.
    final rawCodes = list.map((e) => (e as Map)['code'] ?? e['id'] ?? '<no code/id>').toList();
    debugPrint('[fetchOrders] tab=$tab raw codes (${rawCodes.length}): $rawCodes');
    // CLIENT-REPORTED (2026-08-12): status-swipe revert investigation —
    // also log each order's raw driver_state exactly as the server sent
    // it, so a revert can be traced to "backend genuinely still says
    // pending" vs a client-side parsing issue.
    final rawStates = list.map((e) => '${(e as Map)['code'] ?? e['id']}: ${e['driver_state']}').toList();
    debugPrint('[fetchOrders] tab=$tab raw driver_states: $rawStates');
    final parsed = list.map((e) => Order.fromJson(e)).toList();
    // Defensive: skip any entry with no usable id at all (seen live — an
    // order with blank id AND null co, causing wasted geocode calls
    // ("[HomeMap] geocode FAILED for order  (co=null)") and very likely
    // the intermittent "Order not found" screen too, since a garbage
    // entry like this can appear/disappear between list refreshes.
    final dropped = parsed.where((o) => o.id.isEmpty).length;
    if (dropped > 0) {
      debugPrint('[fetchOrders] tab=$tab DROPPED $dropped entr${dropped == 1 ? "y" : "ies"} with blank id after parsing — this is a parsing bug, not a backend/assignment issue.');
    }
    final rawCounts = res['counts'];
    final counts = <String, int>{
      'active': rawCounts is Map ? (int.tryParse('${rawCounts['active']}') ?? 0) : 0,
      'done': rawCounts is Map ? (int.tryParse('${rawCounts['done']}') ?? 0) : 0,
      'all': rawCounts is Map ? (int.tryParse('${rawCounts['all']}') ?? 0) : 0,
    };
    return (orders: parsed.where((o) => o.id.isNotEmpty).toList(), counts: counts);
  }

  /// CONFIRMED LIVE shape (2026-07-14): {"order": {...fields...}, "items":
  /// [...], "event": ..., "pharmacies": [...]} — fields live under "order",
  /// NOT under "data" and NOT flat at the top level like the list endpoint.
  /// The previous `res['data'] ?? res` unwrapping was wrong: since there's
  /// no "data" key, it silently fell back to the WHOLE raw response, so
  /// every field read as null and produced an Order with a blank id. That
  /// blank-id order then got written back into the in-memory list at
  /// APM74's position (refreshOrder replaces by array position, not by
  /// matching id), corrupting a previously-good entry — which is what
  /// actually caused the intermittent "Order not found" bug, plus the
  /// "geocode FAILED for order  (co=null)" spam. One root cause, several
  /// symptoms.
  Future<Order> fetchOrder(String code) async {
    final res = await _api.get(ApiConfig.path(ApiConfig.orderByCode, {'code': code}));
    debugPrint('[fetchOrder] raw response for $code: $res');
    final orderJson = Map<String, dynamic>.from((res['order'] as Map?) ?? res['data'] ?? res);
    // "items" is a sibling key here, not nested inside "order" — merge it
    // in so Order.fromJson (which looks for j['items']) actually finds it.
    if (res['items'] != null) orderJson['items'] = res['items'];
    // CLIENT-REPORTED (2026-08-12): driver_state was reverting to "pending"
    // every time this screen re-opened after a status swipe. Same root
    // cause as the items fix above, just found later: "pharmacies" is
    // ALSO a sibling key on this endpoint, not nested inside "order" — so
    // it was never being merged in at all here, same class of bug. This
    // alone doesn't explain a driver_state revert though (different
    // field) — the debugPrint above will show the raw driver_state value
    // this endpoint actually returns, which is what's needed to confirm
    // whether that's a similar shape mismatch or a genuine backend
    // persistence issue on /orders/{co}/status.
    if (res['pharmacies'] != null) orderJson['pharmacies'] = res['pharmacies'];
    return Order.fromJson(orderJson);
  }

  /// GET /geocode/{co} — resolves an order's address to real coordinates.
  /// CONFIRMED shape via real logcat responses seen live throughout this
  /// project (e.g. {"lat":null,"lng":null} for an ungeocodable address).
  /// Use this when Order.pinPos is the 0.5/0.5 placeholder (i.e. the
  /// /orders list response didn't include lat/lng) and you need a real
  /// map pin.
  Future<({double lat, double lng})?> geocodeOrder(String co) async {
    final res = await _api.get(ApiConfig.path(ApiConfig.geocode, {'co': co}));
    final data = res['data'] ?? res;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  /// Resolves a Google Maps short link (map_link, e.g.
  /// maps.app.goo.gl/...) to real coordinates by following it and
  /// extracting the coordinates embedded in the resolved page.
  /// CLIENT-ASKED (2026-08-25): moved here from in_app_map_screen.dart
  /// (was a private method there) so it can be reused wherever an
  /// order's location needs resolving — a map_link, when present, is a
  /// human-verified location and generally more reliable than geocoding
  /// free-text address fields, so callers should try this BEFORE falling
  /// back to geocodeOrder above, not skip it.
  ///
  /// Deliberately uses a bare, one-off Dio instance rather than `_api`
  /// (ApiClient): this request goes to Google's servers, not WASFA's
  /// backend, so it must never carry the driver's auth Bearer token or
  /// get prefixed with ApiConfig.baseUrl.
  Future<({double lat, double lng})?> resolveMapLinkCoords(String mapLink) async {
    try {
      final dio = Dio(BaseOptions(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (_) => true, // read whatever comes back; we only need the final URL/body
        responseType: ResponseType.plain, // force a raw String body, never auto-parsed
        // A bare request with no browser-like headers is more likely to
        // get a stripped-down response — Google's short-link landing page
        // for maps.app.goo.gl often redirects via JavaScript rather than
        // a clean HTTP 3xx, so followRedirects alone may never fire.
        // Real headers make it far more likely we get the full page,
        // which still has the resolved coordinates embedded in it even
        // when the redirect itself is JS-driven.
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ));
      final response = await dio.get(mapLink).timeout(const Duration(seconds: 8));
      // Check both the final resolved URL (if an HTTP-level redirect did
      // fire) AND the raw page body (covers the JS-redirect case, where
      // the coordinates are still on the page even though Dio's
      // followRedirects never triggered) — try known coordinate shapes.
      final haystacks = <String>[
        response.realUri.toString(),
        if (response.data is String) response.data as String,
      ];
      for (final text in haystacks) {
        // CONFIRMED LIVE (2026-08-11): this specific link resolved to
        // .../maps/search/10.518035,+76.224552?... — a "search by
        // coordinates" URL, not the /place/...@lat,lng,zoom shape this
        // was originally written for. Try that shape first since it's
        // now confirmed real; keep the other two as fallbacks since a
        // different short link (e.g. one created from a named place
        // rather than a dropped pin) may resolve to a different shape.
        final search = RegExp(r'/search/(-?\d+\.\d+),\+?\s*(-?\d+\.\d+)').firstMatch(text);
        if (search != null) {
          final lat = double.tryParse(search.group(1)!);
          final lng = double.tryParse(search.group(2)!);
          if (lat != null && lng != null) return (lat: lat, lng: lng);
        }
        final at = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
        if (at != null) {
          final lat = double.tryParse(at.group(1)!);
          final lng = double.tryParse(at.group(2)!);
          if (lat != null && lng != null) return (lat: lat, lng: lng);
        }
        final bang = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(text);
        if (bang != null) {
          final lat = double.tryParse(bang.group(1)!);
          final lng = double.tryParse(bang.group(2)!);
          if (lat != null && lng != null) return (lat: lat, lng: lng);
        }
      }
      debugPrint('[OrderRepository] map_link resolved but no coordinate pattern found. '
          'Final URL: ${response.realUri}');
      return null;
    } catch (e) {
      // Network hiccup, unexpected redirect shape, timeout, whatever —
      // this is a nice-to-have pin, not a required step. Callers should
      // never treat this failing as a hard error.
      debugPrint('[OrderRepository] could not resolve map_link coords: $e');
      return null;
    }
  }

  // REMOVED (2026-08-25): postLocation() called a guessed endpoint
  // confirmed to be a genuine 404 — see MapViewModel's own note on why
  // the whole feature was removed, not just this one method.

  /// GET /home — dashboard summary. Shape unconfirmed; returned raw so the
  /// HomeScreen/ViewModel can pull whatever fields backend actually sends
  /// without another round of guessing here.
  Future<Map<String, dynamic>> fetchHome() => _api.get(ApiConfig.home);

  /// Shape unconfirmed for the `period` breakdown specifically — this
  /// endpoint existed but was never actually called anywhere in the app
  /// before now (the Week/Month tabs had no tap handler at all). Returned
  /// raw so the screen can defensively pull out whatever fields actually
  /// come back rather than guessing a strict model up front.
  Future<Map<String, dynamic>> fetchEarnings({String period = 'today'}) =>
      _api.get(ApiConfig.earnings, query: {'period': period});

  // ── Delivery flow ────────────────────────────────────────────
  /// CONFIRMED v2 — generic status update, notifies the seller when
  /// status is 'collecting'. Valid values per backend: 'collecting',
  /// 'picked_up', 'on_the_way'.
  /// [lat]/[lng] — driver's GPS position at the moment of the status
  /// change (client-requested, added so backend can log/show where the
  /// driver actually was at each step). Omitted from the body entirely
  /// when unavailable (permission denied, GPS off, no fix yet) rather
  /// than sending nulls, so a missing fix never crashes/blocks the
  /// status update itself.
  Future<void> updateStatus(String co, String status, {double? lat, double? lng}) => _api.post(
    ApiConfig.path(ApiConfig.updateStatus, {'co': co}),
    data: {
      'status': status,
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
    },
  );

  /// SUPERSEDED (2026-08-18) — see ApiConfig.reorderAll for why: the
  /// per-order endpoint this used to call needed a loop of calls for
  /// anything beyond a single swap. Now sends the WHOLE new sequence
  /// (co numeric ids, first = top priority) in one JSON POST — no
  /// looping, and no ambiguity for backend to resolve differently since
  /// the app is dictating the entire order itself. Response is minimal
  /// ({"ok": true, "updated": n}) — nothing to reconcile against.
  Future<void> reorderActive(List<String> coIds) =>
      _api.post(ApiConfig.reorderAll, data: {'order': coIds.map(int.parse).toList()});

  Future<void> arrive(String co) =>
      _api.post(ApiConfig.path(ApiConfig.arrive, {'co': co}));

  /// "Pharmacy pickup (single order)" — for an order that itself spans
  /// multiple pharmacies (Order.multiPharmacy / Order.pharmacies).
  /// CLIENT-CONFIRMED (2026-08-19) via a real SQL error from backend
  /// itself: the "v3" note claiming {seller} should be the pharmacy
  /// NAME was wrong. Backend's own error — "Incorrect integer value:
  /// 'Pharmaline Pharmacy' for column ... seller_id" — proves that
  /// column is numeric; sending the name was guaranteed to fail every
  /// single time. [sellerId] is now the pharmacy's numeric seller id.
  /// CLIENT-CONFIRMED LIVE (2026-08-19): with the fix above, this now
  /// actually succeeds and returns the full, authoritative pharmacies
  /// array for the order — {"ok":true,"pharmacies":[...],
  /// "picked_count":1,"pharmacy_count":2} — scoped correctly to just
  /// the requested seller (the other pharmacy in the same test order
  /// stayed picked_up:false). Returns that array so the caller can
  /// reconcile local state against backend's own answer rather than
  /// just trusting the optimistic local guess — same pattern already
  /// used for reorderActive's response.
  Future<List<Pharmacy>> pickupSeller(String co, int sellerId) async {
    final res = await _api.post(
      ApiConfig.path(ApiConfig.pickupSeller, {'co': co, 'seller': '$sellerId'}),
    );
    final list = (res['pharmacies'] as List?) ?? const [];
    return list.map((e) => Pharmacy.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// POST /orders/{co}/finish — CONFIRMED v3: the example body only shows
  /// `pod_photo`. Making it required now; method/given/signature are kept
  /// as OPTIONAL extra fields (harmless if backend ignores them) rather
  /// than removed outright, since deleting the payment-confirmation flow
  /// on a single ambiguous example seemed riskier than sending a few
  /// possibly-unused fields. Confirm with backend whether cash/knet/link
  /// collection still happens here.
  /// [signature] is expected to be a base64 PNG string (adjust if backend
  /// wants a file upload instead — swap for MultipartFile.fromFile).
  Future<void> finish(
      String co, {
        required String podPhotoPath,
        String? method,
        String? given,
        String? signatureBase64,
      }) async {
    final form = FormData.fromMap({
      'pod_photo': await MultipartFile.fromFile(podPhotoPath),
      if (method != null) 'method': method,
      if (given != null) 'given': given,
      if (signatureBase64 != null) 'signature': signatureBase64,
    });
    await _api.postMultipart(ApiConfig.path(ApiConfig.finish, {'co': co}), form);
  }

  /// Maps an Order to the 'cash'|'knet'|'paid' value /finish expects.
  /// Already-paid orders (online/link, paid==true) send 'paid'; cash/knet
  /// orders still being collected send their own method.
  static String methodForOrder(Order o) {
    if (o.paid) return 'paid';
    return o.payMethod == PayMethod.knet ? 'knet' : 'cash';
  }

  /// POST /orders/{co}/fail — CONFIRMED v3 body is just {"reason": "..."}.
  /// The `reattempt` field from the older guess is gone. [reason] should be
  /// a stable value, not the driver's currently-selected UI language's
  /// translated text (see FailedDeliveryScreen — it sends a fixed English
  /// descriptive string per reason, chosen precisely so language switching
  /// can never change what the backend receives).
  Future<void> fail(String co, {required String reason}) =>
      _api.post(
        ApiConfig.path(ApiConfig.fail, {'co': co}),
        data: {'reason': reason},
      );

  // ── Building photos ────────────────────────────────────────────
  /// CONFIRMED LIVE (2026-07-14): {"photos": [{"id":1, "url":"...",
  /// "note":null, "by":"Zeidan Mohamed", "created_at":"..."}]} — each
  /// entry is an OBJECT, not a plain URL string. The previous
  /// `.toString()` on each raw map produced a garbage debug-string
  /// ("{id: 1, url: ..., note: null, ...}") instead of the real URL,
  /// which is exactly why every photo silently failed to load and fell
  /// back to the placeholder — never a data problem, always this parsing bug.
  Future<List<BuildingPhoto>> fetchBuildingPhotos(String co) async {
    final res = await _api.get(ApiConfig.path(ApiConfig.buildingPhotosGet, {'co': co}));
    final list = (res['photos'] ?? res['data'] ?? const []) as List;
    return list.map((e) => BuildingPhoto.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// POST /orders/{co}/building-photos — field name CONFIRMED LIVE as
  /// `file` (2026-07-14): a real request with `photo` got back
  /// {"message":"The file field is required.","errors":{"file":[...]}} —
  /// so the previous "CONFIRMED v3" comment claiming `photo` was actually
  /// wrong. `customer_id` is optional; see order_detail_screen.dart for
  /// why it's not sent (order.id would misidentify the customer).
  Future<void> uploadBuildingPhoto(String co, String filePath, {String? customerId}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (customerId != null) 'customer_id': customerId,
    });
    await _api.postMultipart(
      ApiConfig.path(ApiConfig.buildingPhotosPost, {'co': co}),
      form,
    );
  }

  // ── Shift / vehicle / language ────────────────────────────────
  /// CONFIRMED v3: body key is `on_shift`, NOT `online` like guessed before.
  Future<void> setShift(bool onShift) =>
      _api.post(ApiConfig.shift, data: {'on_shift': onShift});

  Future<void> setVehicle({required String vehicleType, required String plateNumber}) =>
      _api.post(ApiConfig.vehicle, data: {
        'vehicle_type': vehicleType,
        'plate_number': plateNumber,
      });

  Future<void> setLanguage(String language) =>
      _api.post(ApiConfig.language, data: {'language': language});

  // ── Batch ────────────────────────────────────────────────────
  /// CONFIRMED v2 top-level shape: {batch, stops, summary, pharmacy_stops}.
  /// `batch` presumably holds pharmacy/batch metadata, `stops` the order
  /// list (still guessing they look like Order-shaped entries — field
  /// names inside `batch`/`stops`/`pharmacy_stops` are NOT confirmed).
  /// `summary` and `pharmacy_stops` are exposed raw on Batch so UI can use
  /// them directly without another guessed model.
  Future<Batch?> fetchPendingBatch() async {
    final res = await _api.get(ApiConfig.batch);
    if (res['batch'] == null && res['stops'] == null) return null;
    return Batch.fromApiResponse(res);
  }

  /// GET /batch-check — lightweight poll to see if a new batch offer
  /// exists, without pulling the full payload. Shape unconfirmed.
  Future<bool> checkForNewBatch() async {
    final res = await _api.get(ApiConfig.batchCheck);
    return (res['available'] ?? res['has_batch'] ?? false) == true;
  }

  Future<void> acceptBatch(String batchId) =>
      _api.post(ApiConfig.path(ApiConfig.batchAccept, {'batch_id': batchId}));

  Future<void> rejectBatch(String batchId) =>
      _api.post(ApiConfig.path(ApiConfig.batchReject, {'batch_id': batchId}));

  // ── Multi-stop pickup (within an accepted batch) ─────────────
  /// Same confirmed shape as /batch: {batch, stops, summary, pharmacy_stops}.
  Future<Batch?> fetchPickupState() async {
    final res = await _api.get(ApiConfig.pickup);
    if (res['batch'] == null && res['stops'] == null) return null;
    return Batch.fromApiResponse(res);
  }

  Future<void> startPickup() => _api.post(ApiConfig.pickupStart);

  /// CONFIRMED v3 — REPLACES the v2 guess entirely. `seller` is a NAME
  /// string (e.g. "Royal Pharmacy"), matching the {co}/pickup/{seller} URL
  /// param — NOT a numeric seller_id like v2's collection suggested.
  Future<void> togglePharmacyCollected(String sellerName) =>
      _api.post(ApiConfig.pickupPharmacy, data: {'seller': sellerName});

  /// CONFIRMED v3 — REPLACES the old "legacy" combined_order_id guess
  /// entirely. Now takes the pharmacy NAME plus an explicit on/off
  /// [picked] flag, matching [togglePharmacyCollected]'s seller concept
  /// rather than being order-based.
  Future<void> setPickupToggle(String sellerName, bool picked) =>
      _api.post(ApiConfig.pickupToggle, data: {'seller': sellerName, 'picked': picked});

  // ── Profile (KYC form) ─────────────────────────────────────────
  /// GET /profile — CONFIRMED shape (seen live): {"profile": {...}}.
  Future<Map<String, dynamic>> fetchProfile() async {
    final res = await _api.get(ApiConfig.profileGet);
    return (res['profile'] ?? res['data'] ?? res) as Map<String, dynamic>;
  }

  /// POST /profile — CONFIRMED exact field list from the real request body:
  /// full_name, name_ar, email, phone, civil_id, nationality, blood_group,
  /// languages_spoken (array), company_name, employee_id,
  /// driving_experience_years, home_area, home_block, home_street,
  /// home_building, emergency_name, emergency_phone,
  /// emergency_relationship, vehicle_type, plate_number, vehicle_make,
  /// vehicle_model, vehicle_color, bank_name, bank_iban, bank_beneficiary.
  Future<void> saveProfile(Map<String, dynamic> body) =>
      _api.post(ApiConfig.profileUpdate, data: body);

  /// POST /profile/document — multipart {slot, file}. CONFIRMED valid
  /// slot values: doc_civil_id_front | doc_civil_id_back |
  /// doc_license_front | doc_license_back | doc_vehicle_registration |
  /// doc_vehicle_insurance.
  Future<void> uploadProfileDocument(String slot, String filePath) async {
    final form = FormData.fromMap({
      'slot': slot,
      'file': await MultipartFile.fromFile(filePath),
    });
    await _api.postMultipart(ApiConfig.profileDocument, form);
  }

  /// CONFIRMED LIVE from Postman (2026-07-15): multipart field is "photo",
  /// not "file" like every other upload endpoint in this API — this one's
  /// the odd one out, so don't copy this field name elsewhere by habit.
  /// Still don't know where the resulting photo URL comes back from
  /// (this response, or a new field on /me) — debugPrint below will show
  /// the real response the first time this actually runs.
  Future<Map<String, dynamic>> uploadProfilePhoto(String filePath) async {
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(filePath),
    });
    final res = await _api.postMultipart(ApiConfig.profilePhoto, form);
    debugPrint('[ProfilePhoto] upload response: $res');
    return res;
  }

  // ── Cash handover (Company Cash tab) ─────────────────────────────

  /// STILL UNCONFIRMED — a completely separate endpoint from
  /// fetchCashHandovers below. Not currently called anywhere (the
  /// Company Cash screen now sources its "cash to hand over" figure from
  /// fetchCashHandovers's total_pending instead, which IS confirmed
  /// live). Left here in case backend ever builds this as a distinct
  /// thing — don't assume it returns the same number.
  Future<double> fetchCashBalance() async {
    final res = await _api.get(ApiConfig.cashBalance);
    debugPrint('[CashBalance] raw response: $res');
    return (res['amount'] ?? res['balance'] ?? 0).toDouble();
  }

  /// CONFIRMED LIVE (2026-08-11) via Postman: GET /driver/cash-handovers
  /// returns { handovers: [...], total_handed_over, total_pending,
  /// currency }. Returns the full summary (not just the bare list) so
  /// callers use backend's own running totals instead of re-summing
  /// whatever page of records this returns.
  Future<CashHandoverSummary> fetchCashHandovers() async {
    final res = await _api.get(ApiConfig.cashHandovers);
    debugPrint('[CashHandovers] raw response: $res');
    return CashHandoverSummary.fromJson(res);
  }

  Future<CashHandoverSession> startCashHandover() async {
    final res = await _api.post(ApiConfig.cashHandoverStart);
    return CashHandoverSession.fromJson(res);
  }

  /// Returns 'pending' | 'confirmed' | 'expired' (best guess — unconfirmed).
  Future<String> getCashHandoverStatus(String handoverId) async {
    final res = await _api.get(ApiConfig.path(ApiConfig.cashHandoverStatus, {'id': handoverId}));
    return (res['status'] ?? 'pending').toString();
  }
}
