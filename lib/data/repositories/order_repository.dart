import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../models/models.dart';

/// Replaces the old seed-data OrderRepository with real API calls.
/// `id` on Order is the order `code` (e.g. "APM10061"). Some routes
/// (arrive/pickup/finish/fail/building-photos/geocode) use `{co}`, which
/// per the Postman collection looks like a *numeric* order id, separate
/// from the human-readable `code`. UNCONFIRMED whether `co` == `code` or
/// a different internal id — if delivery-flow calls 404, this is the
/// first thing to check with backend. For now this repo assumes co == code.
class OrderRepository {
  final _api = ApiClient.instance;

  Future<List<Order>> fetchOrders({String tab = 'active'}) async {
    final res = await _api.get(ApiConfig.orders, query: {'tab': tab});
    // CONFIRMED v2: top-level key is "list", not "data"/"orders".
    final list = (res['list'] ?? res['data'] ?? res['orders'] ?? const []) as List;
    // Defensive: skip any entry with no usable id at all (seen live — an
    // order with blank id AND null co, causing wasted geocode calls
    // ("[HomeMap] geocode FAILED for order  (co=null)") and very likely
    // the intermittent "Order not found" screen too, since a garbage
    // entry like this can appear/disappear between list refreshes.
    return list.map((e) => Order.fromJson(e)).where((o) => o.id.isNotEmpty).toList();
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
    final orderJson = Map<String, dynamic>.from((res['order'] as Map?) ?? res['data'] ?? res);
    // "items" is a sibling key here, not nested inside "order" — merge it
    // in so Order.fromJson (which looks for j['items']) actually finds it.
    if (res['items'] != null) orderJson['items'] = res['items'];
    return Order.fromJson(orderJson);
  }

  /// GET /geocode/{co} — resolves an order's address to real coordinates.
  /// UNCONFIRMED response shape — guessing {"lat": .., "lng": ..}. Use
  /// this when Order.pinPos is the 0.5/0.5 placeholder (i.e. the /orders
  /// list response didn't include lat/lng) and you need a real map pin.
  Future<({double lat, double lng})?> geocodeOrder(String co) async {
    final res = await _api.get(ApiConfig.path(ApiConfig.geocode, {'co': co}));
    final data = res['data'] ?? res;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

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
  Future<void> updateStatus(String co, String status) =>
      _api.post(ApiConfig.path(ApiConfig.updateStatus, {'co': co}), data: {'status': status});

  Future<void> arrive(String co) =>
      _api.post(ApiConfig.path(ApiConfig.arrive, {'co': co}));

  /// "Pharmacy pickup (single order)" — for an order that itself spans
  /// multiple pharmacies (Order.multiPharmacy / PharmacyPickup list).
  /// [sellerId] is the pharmacy's numeric seller id.
  Future<void> pickupSeller(String co, String sellerId) => _api.post(
    ApiConfig.path(ApiConfig.pickupSeller, {'co': co, 'seller': sellerId}),
  );

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

  // ── Cash handover (Company Cash tab) — backend not built yet ────
  // See api_config.dart for the "not confirmed" caveat on all of these.

  /// CONFIRMED path from Postman (2026-07-15): GET /driver/cash-balance.
  /// No example response saved though — field names below (amount/balance)
  /// are still a guess. Logs the raw response so the real shape shows up
  /// in logcat the first time this actually gets called.
  Future<double> fetchCashBalance() async {
    final res = await _api.get(ApiConfig.cashBalance);
    debugPrint('[CashBalance] raw response: $res');
    return (res['amount'] ?? res['balance'] ?? 0).toDouble();
  }

  /// CONFIRMED path from Postman (2026-07-15): GET /driver/cash-handovers.
  /// Same caveat — no example response, field names still a guess.
  Future<List<CashHandoverRecord>> fetchCashHandovers() async {
    final res = await _api.get(ApiConfig.cashHandovers);
    debugPrint('[CashHandovers] raw response: $res');
    final list = (res['data'] ?? res['handovers'] ?? const []) as List;
    return list.map((e) => CashHandoverRecord.fromJson(e as Map<String, dynamic>)).toList();
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
