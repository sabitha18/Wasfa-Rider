import 'package:flutter/material.dart';

// ── Enums ──────────────────────────────────────────────────────
enum OrderStatus { active, next, later, done, failed, batchPending }
enum DriverState { pending, collecting, pickedUp, onMyWay, delivered, failed }
enum PayMethod  { cash, knet, online, link }
enum VehicleType { motorbike, scooter, car }

// ── Order Item ─────────────────────────────────────────────────
class OrderItem {
  final String name;
  final double price;
  final int qty;
  final Color color;
  final String tag;        // e.g. 'OTC', 'Rx', 'D2'
  final String? pharmacy;  // seller pharmacy name
  // NOT CONFIRMED — backend's item shape has no image field at all yet
  // (see fromJson comment below). Parsed defensively against a few likely
  // key names so this starts working the moment backend adds one, without
  // needing another round of client changes.
  final String? imageUrl;

  const OrderItem({
    required this.name,
    required this.price,
    this.qty = 1,
    this.color = const Color(0xFFE8646A),
    this.tag = 'Rx',
    this.pharmacy,
    this.imageUrl,
  });

  // CONFIRMED shape (seen live): {name, quantity, price, tag, pharmacy}
  // Note the key is "quantity", not "qty". No image field currently exists
  // in this response — imageUrl below is a forward-compatible guess at
  // possible key names, not a confirmed one.
  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
    name: j['name'] ?? '',
    price: (j['price'] ?? 0).toDouble(),
    qty: j['quantity'] ?? j['qty'] ?? 1,
    tag: j['tag'] ?? 'Rx',
    pharmacy: j['pharmacy'],
    color: _colorForTag(j['tag']),
    imageUrl: j['image_url'] ?? j['image'] ?? j['photo_url'] ?? j['photo'],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'quantity': qty,
    'tag': tag,
    'pharmacy': pharmacy,
  };

  static Color _colorForTag(String? tag) {
    switch (tag) {
      case 'OTC': return const Color(0xFFE8646A);
      case 'D2': return const Color(0xFFED8936);
      default: return const Color(0xFF4299E1); // Rx
    }
  }
}

// ── Pharmacy Pickup (multi-pharmacy orders) ────────────────────
// ── Building photo (per-address photo shared between drivers) ──
class BuildingPhoto {
  final String url;
  final String? note;
  final String? by;
  const BuildingPhoto({required this.url, this.note, this.by});

  factory BuildingPhoto.fromJson(Map<String, dynamic> j) => BuildingPhoto(
    url: (j['url'] ?? '').toString(),
    note: j['note'],
    by: j['by'],
  );
}

// ── Cash handover (Company Cash tab) ─────────────────────────────
// CONFIRMED LIVE (2026-08-11) via Postman: GET /driver/cash-handovers
// returns { handovers: [...], total_handed_over, total_pending, currency }.
// Each handover: { co_id, code, amount, status, confirmed, confirmed_by,
// handover_date, date_label }. Two things the earlier guessed shape got
// wrong, now fixed: `amount` comes back as a STRING ("28.600"), not a
// number — calling .toDouble() on that would have crashed the first time
// this endpoint was actually hit; and there is no `method` field at all,
// so isBank below is inert (kept only so nothing else needs to change)
// until/unless backend ever adds one.
class CashHandoverSession {
  final String id;
  final String qrData; // full URL or token — whatever should be encoded in the QR
  final String code;   // 6-digit manual-entry code
  final double amount;
  final DateTime? expiresAt;

  const CashHandoverSession({
    required this.id,
    required this.qrData,
    required this.code,
    required this.amount,
    this.expiresAt,
  });

  factory CashHandoverSession.fromJson(Map<String, dynamic> j) => CashHandoverSession(
    id: (j['handover_id'] ?? j['id'] ?? '').toString(),
    qrData: (j['qr_url'] ?? j['url'] ?? j['token'] ?? '').toString(),
    code: (j['code'] ?? '').toString(),
    amount: (j['amount'] ?? 0).toDouble(),
    expiresAt: j['expires_at'] != null ? DateTime.tryParse(j['expires_at']) : null,
  );
}

class CashHandoverRecord {
  final int? coId;
  final String? code;
  final double amount;
  final bool isBank;
  final String dateLabel;
  final String? confirmedBy;
  final bool pending;

  const CashHandoverRecord({
    this.coId,
    this.code,
    required this.amount,
    this.isBank = false,
    required this.dateLabel,
    this.confirmedBy,
    this.pending = false,
  });

  factory CashHandoverRecord.fromJson(Map<String, dynamic> j) => CashHandoverRecord(
    coId: j['co_id'] is int ? j['co_id'] as int : int.tryParse('${j['co_id']}'),
    code: j['code']?.toString(),
    // amount is a STRING in the real response ("28.600") — .toDouble()
    // doesn't exist on String and would throw. Parse it properly.
    amount: double.tryParse('${j['amount']}') ?? 0.0,
    isBank: (j['method'] ?? '') == 'bank', // no such field exists yet — always false today
    dateLabel: (j['date_label'] ?? j['handover_date'] ?? '').toString(),
    confirmedBy: j['confirmed_by']?.toString(),
    // Use backend's own explicit boolean rather than string-matching
    // status — more robust if a third status value ever shows up.
    pending: j['confirmed'] != true,
  );
}

/// Wraps the handover list together with backend's own running totals.
/// Use [totalHandedOver]/[totalPending] directly rather than summing
/// [records] locally — this endpoint may only return a recent page of
/// history, not the driver's complete record, so a local sum could
/// under-count.
class CashHandoverSummary {
  final List<CashHandoverRecord> records;
  final double totalHandedOver;
  final double totalPending;
  final String currency;

  const CashHandoverSummary({
    required this.records,
    required this.totalHandedOver,
    required this.totalPending,
    required this.currency,
  });

  factory CashHandoverSummary.fromJson(Map<String, dynamic> j) {
    final list = (j['handovers'] ?? j['data'] ?? const []) as List;
    return CashHandoverSummary(
      records: list.map((e) => CashHandoverRecord.fromJson(e as Map<String, dynamic>)).toList(),
      totalHandedOver: double.tryParse('${j['total_handed_over'] ?? 0}') ?? 0.0,
      totalPending: double.tryParse('${j['total_pending'] ?? 0}') ?? 0.0,
      currency: (j['currency'] ?? 'KD').toString(),
    );
  }
}

class PharmacyPickup {
  final String phId;
  final String name;
  final String addr;
  final List<String> items;
  bool picked;
  Map<String, bool> itemsPicked;

  PharmacyPickup({
    required this.phId,
    required this.name,
    required this.addr,
    required this.items,
    this.picked = false,
    Map<String, bool>? itemsPicked,
  }) : itemsPicked = itemsPicked ?? {};

  PharmacyPickup copyWith({bool? picked, Map<String, bool>? itemsPicked}) =>
      PharmacyPickup(
        phId: phId, name: name, addr: addr, items: items,
        picked: picked ?? this.picked,
        itemsPicked: itemsPicked ?? this.itemsPicked,
      );

  factory PharmacyPickup.fromJson(Map<String, dynamic> j) => PharmacyPickup(
    phId: j['phId'] ?? j['id'] ?? '',
    name: j['name'] ?? '',
    addr: j['addr'] ?? j['address'] ?? '',
    items: List<String>.from(j['items'] ?? const []),
    picked: j['picked'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'phId': phId, 'name': name, 'addr': addr, 'items': items, 'picked': picked,
  };
}

// ── Call / Escalation request ──────────────────────────────────
class CallRequest {
  final String from;
  final String by;
  final DateTime at;
  final String note;
  String status; // pending | accepted | rejected
  String? rejectionReason;
  String? rejectionNote;

  CallRequest({
    required this.from, required this.by, required this.at,
    required this.note, this.status = 'pending',
    this.rejectionReason, this.rejectionNote,
  });
}

class CallEscalation {
  final DateTime at;
  String status; // pending | resolved

  CallEscalation({required this.at, this.status = 'pending'});
}

// ── Pin position on the mock map ──────────────────────────────
class PinPos {
  final double leftFraction; // 0.0 – 1.0
  final double topFraction;

  const PinPos(this.leftFraction, this.topFraction);
}

// ── Pharmacy (pickup location for an order's items) ─────────────
// CONFIRMED LIVE (2026-08-12) via Postman: GET /orders?tab=all includes a
// `pharmacies` array per order: [{seller_id, name, phone, address, lat,
// lang, items_count}]. NOTE the real field is "lang", not "lng" — a
// backend typo specific to this array (the order-level destination field
// is spelled correctly as "lng"). Easy to miss and silently get 0.0/null
// longitude for every pharmacy if copy-pasted from the order-level
// parsing without checking this.
/// One item within a pharmacy's nested "items" array (order-detail
/// endpoint only — see Pharmacy class doc). Distinct from the top-level
/// OrderItem class since this comes from a differently-shaped nested
/// structure and doesn't carry a tag/image/pharmacy-name of its own
/// (it's already scoped to one specific pharmacy by construction).
class PharmacyItem {
  final String name;
  final int quantity;
  final double price;
  const PharmacyItem({required this.name, this.quantity = 1, this.price = 0});

  factory PharmacyItem.fromJson(Map<String, dynamic> j) => PharmacyItem(
    name: (j['name'] ?? '').toString(),
    quantity: j['quantity'] is int ? j['quantity'] as int : int.tryParse('${j['quantity']}') ?? 1,
    price: j['price'] != null ? (j['price'] as num).toDouble() : 0,
  );
}

class Pharmacy {
  final int? sellerId;
  final String name;
  final String? phone;
  final String? address;
  final double? lat;
  final double? lng;
  final int itemsCount;
  // Full item objects from the order-detail endpoint's nested "items"
  // array (see fromJson) — empty on the list endpoint's shape, which
  // has no nested items at all, only a plain items_count number.
  final List<PharmacyItem> items;
  // CONFIRMED LIVE (2026-08-19) on the order-detail endpoint — this
  // pharmacy's own share of the order total. Falls back to summing
  // `items` when absent (e.g. on the list endpoint's shape).
  final double subtotal;
  final bool pickedUp;
  final DateTime? pickedAt;

  const Pharmacy({
    this.sellerId,
    required this.name,
    this.phone,
    this.address,
    this.lat,
    this.lng,
    this.itemsCount = 0,
    this.items = const [],
    this.subtotal = 0,
    this.pickedUp = false,
    this.pickedAt,
  });

  // Kept for the existing fallback lookup in order_detail_screen.dart's
  // _ItemsCard, which only needs names, not full item objects.
  List<String> get itemNames => items.map((i) => i.name).where((n) => n.isNotEmpty).toList();

  bool get hasCoords => lat != null && lng != null;

  Pharmacy copyWith({bool? pickedUp, DateTime? pickedAt}) => Pharmacy(
    sellerId: sellerId, name: name, phone: phone, address: address, lat: lat, lng: lng,
    itemsCount: itemsCount, items: items, subtotal: subtotal,
    pickedUp: pickedUp ?? this.pickedUp, pickedAt: pickedAt ?? this.pickedAt,
  );

  // CLIENT-REPORTED (2026-08-18): confirmed live — the order-DETAIL
  // endpoint (GET /orders/{code}) returns pharmacies in a DIFFERENT shape
  // than the list endpoint (GET /orders?tab=all): "area" instead of
  // "address", correctly-spelled "lng" instead of the list endpoint's
  // "lang" typo, and a nested "items" array instead of a plain
  // "items_count" number. Only "name" happens to be spelled the same in
  // both, which is why that one field was never affected. Checks both
  // known key names for everything else, and falls back to summing the
  // nested items' quantities when items_count isn't present at all.
  factory Pharmacy.fromJson(Map<String, dynamic> j) {
    final itemsArray = (j['items'] as List?) ?? const [];
    final parsedItems = itemsArray.map((e) => PharmacyItem.fromJson(e as Map<String, dynamic>)).toList();
    final summedQuantity = parsedItems.fold<int>(0, (sum, i) => sum + i.quantity);
    final summedPrice = parsedItems.fold<double>(0, (sum, i) => sum + i.price * i.quantity);
    return Pharmacy(
      sellerId: j['seller_id'] is int ? j['seller_id'] as int : int.tryParse('${j['seller_id']}'),
      name: (j['name'] ?? '').toString(),
      phone: j['phone']?.toString(),
      address: (j['address'] ?? j['area'])?.toString(),
      lat: j['lat'] != null ? (j['lat'] as num).toDouble() : null,
      lng: (j['lang'] ?? j['lng']) != null ? ((j['lang'] ?? j['lng']) as num).toDouble() : null,
      items: parsedItems,
      subtotal: j['subtotal'] != null ? (j['subtotal'] as num).toDouble() : summedPrice,
      itemsCount: j['items_count'] is int
          ? j['items_count'] as int
          : (int.tryParse('${j['items_count']}') ?? (itemsArray.isNotEmpty ? summedQuantity : 0)),
      pickedUp: j['picked_up'] == true,
      pickedAt: j['picked_at'] != null ? DateTime.tryParse('${j['picked_at']}') : null,
    );
  }
}

// ── Order ──────────────────────────────────────────────────────
class Order {
  final String id; // the human-readable `code`, e.g. "APM10061" — used for display + GET /orders/{code}
  final String? co; // CONFIRMED to be a DIFFERENT, numeric internal id (Postman example: code="APM5" vs co="6")
  // used by arrive/pickup/finish/fail/status/building-photos/geocode.
  // Field name inside the real order JSON for this is still UNCONFIRMED —
  // guessing `id` below since `code` already claims that name in our own model.
  final int stopNumber;
  final String patient;
  final String phone;
  final String addr1;
  final String addr2;
  final String? landmark;
  final String? customerNote;
  final List<OrderItem> items;
  final double total;
  final bool paid;
  final PayMethod payMethod;
  final double? discount;
  final double? deliveryFee;
  OrderStatus status;
  DriverState driverState;
  final double distanceKm;
  final int etaMin;
  final PinPos pinPos;
  // CONFIRMED LIVE (2026-08-12): each order can list multiple pharmacy
  // pickup locations — see Pharmacy class above for the field-name caveat.
  final List<Pharmacy> pharmacies;
  // CONFIRMED LIVE (2026-08-11): when lat/lng are null, backend may still
  // send a real Google Maps link (e.g. a POS-pasted short link like
  // https://maps.app.goo.gl/...). Short links don't carry lat/lng in the
  // URL itself (that only appears after Google's server resolves the
  // redirect), so this can't feed the in-app pin directly — but it's a
  // guaranteed-accurate destination for external Google Maps navigation,
  // which is what actually matters for "I can't get directions."
  final String? mapLink;
  // CONFIRMED LIVE (2026-08-13): a real, working payment link comes back
  // directly on the order — no separate "generate link" endpoint needed
  // at all. Tap Payments url-shortener, e.g.
  // https://url-shortner.sandbox.tap.company/i/FSFRIUHIBT.
  final String? paymentLink;
  final String? transactionId;
  final bool multiPharmacy;
  // CLIENT-CONFIRMED LIVE (2026-08-19): backend added these two fields
  // to the list endpoint specifically for the "Collecting (X/Y)" badge —
  // no need to derive this from order.pharmacies client-side, since the
  // list endpoint's own pharmacies entries (when present at all) don't
  // carry picked_up per pharmacy the way the detail endpoint's do.
  final int? pharmaciesPicked;
  final int? pharmaciesTotal;
  final List<PharmacyPickup> pickups;
  DateTime? deliveredAt;
  String? failureReason;
  CallRequest? callRequest;
  CallEscalation? callEscalation;
  // SLA: created-at timestamp and SLA window in minutes
  final DateTime createdAt;
  final int slaMinutes;

  Order({
    required this.id,
    this.co,
    required this.stopNumber,
    required this.patient,
    required this.phone,
    required this.addr1,
    required this.addr2,
    this.landmark,
    this.customerNote,
    required this.items,
    required this.total,
    required this.paid,
    required this.payMethod,
    this.discount,
    this.deliveryFee,
    required this.status,
    required this.driverState,
    required this.distanceKm,
    required this.etaMin,
    required this.pinPos,
    this.pharmacies = const [],
    this.mapLink,
    this.paymentLink,
    this.transactionId,
    this.multiPharmacy = false,
    this.pharmaciesPicked,
    this.pharmaciesTotal,
    List<PharmacyPickup>? pickups,
    this.deliveredAt,
    this.failureReason,
    this.callRequest,
    this.callEscalation,
    DateTime? createdAt,
    this.slaMinutes = 30,
  })  : pickups = pickups ?? [],
        createdAt = createdAt ?? DateTime.now().subtract(const Duration(minutes: 15));

  Order copyWith({
    int? stopNumber,
    OrderStatus? status,
    DriverState? driverState,
    DateTime? deliveredAt,
    String? failureReason,
    CallRequest? callRequest,
    CallEscalation? callEscalation,
    List<PharmacyPickup>? pickups,
    List<Pharmacy>? pharmacies,
  }) {
    return Order(
      id: id, co: co, stopNumber: stopNumber ?? this.stopNumber, patient: patient, phone: phone,
      addr1: addr1, addr2: addr2, landmark: landmark, customerNote: customerNote,
      items: items, total: total, paid: paid, payMethod: payMethod,
      discount: discount, deliveryFee: deliveryFee,
      status: status ?? this.status,
      driverState: driverState ?? this.driverState,
      distanceKm: distanceKm, etaMin: etaMin, pinPos: pinPos, pharmacies: pharmacies ?? this.pharmacies, mapLink: mapLink,
      paymentLink: paymentLink, transactionId: transactionId,
      multiPharmacy: multiPharmacy,
      pharmaciesPicked: pharmaciesPicked, pharmaciesTotal: pharmaciesTotal,
      pickups: pickups ?? this.pickups,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      failureReason: failureReason ?? this.failureReason,
      callRequest: callRequest ?? this.callRequest,
      callEscalation: callEscalation ?? this.callEscalation,
      createdAt: createdAt, slaMinutes: slaMinutes,
    );
  }

  // SLA timing
  DateTime get slaTarget => createdAt.add(Duration(minutes: slaMinutes));
  Duration get slaRemaining => slaTarget.difference(DateTime.now());
  bool get isLate => slaRemaining.isNegative;
  double get slaProgress => (DateTime.now().difference(createdAt).inSeconds /
      Duration(minutes: slaMinutes).inSeconds).clamp(0.0, 1.0);

  // Driver-state helpers
  bool get isDelivered => status == OrderStatus.done || deliveredAt != null;
  bool get hasPendingCallRequest => callRequest?.status == 'pending' && callRequest?.from == 'dispatcher';
  bool get hasPendingEscalation  => callEscalation?.status == 'pending';
  // CLIENT-REQUESTED (2026-08-13): Maps/Waze/Call were always pointed at
  // the customer, even during "heading to pharmacy"/"collecting" — the
  // two steps where the driver actually needs to get to the PHARMACY,
  // not the customer. Only from pickedUp onward does the customer's
  // address become the right target again.
  bool get isHeadingToPharmacy => driverState == DriverState.pending || driverState == DriverState.collecting;
  // Multi-pharmacy orders have their own dedicated pickup-checklist
  // screen for sequencing through all of them; this is just "the one
  // relevant right now" for a quick Maps/Waze/Call action, so the first
  // pharmacy is a reasonable single target rather than trying to guess
  // which one is next from here.
  Pharmacy? get primaryPharmacy => pharmacies.isNotEmpty ? pharmacies.first : null;

  // CLIENT-REPORTED (2026-08-22): once the driver marks the first of
  // several pharmacies picked up, Home's card and its Maps/Call buttons
  // kept showing that same first pharmacy forever — primaryPharmacy
  // always returns pharmacies.first regardless of picked status. This
  // returns whichever pharmacy still needs collecting (in array order),
  // falling back to primaryPharmacy once everything's picked (or for a
  // single-pharmacy order, where this is equivalent to primaryPharmacy
  // anyway since pickedUp tracking is only meaningful for multi-pharmacy
  // orders).
  Pharmacy? get nextUnpickedPharmacy {
    for (final p in pharmacies) {
      if (!p.pickedUp) return p;
    }
    return primaryPharmacy;
  }

  // For map pin colour
  Color get pinColor {
    switch (status) {
      case OrderStatus.done:        return const Color(0xFF21B47A);
      case OrderStatus.active:      return const Color(0xFFE7609F);
      case OrderStatus.next:        return const Color(0xFF023B60);
      case OrderStatus.later:       return const Color(0xFF58C4E4);
      case OrderStatus.failed:      return const Color(0xFFE5484D);
      case OrderStatus.batchPending: return const Color(0xFF58C4E4);
    }
  }

  // ── API mapping ─────────────────────────────────────────────
  // CONFIRMED shape (seen live from GET /orders?tab=active, top key "list"):
  // {id, co_id, stop_number, patient, phone, phone_intl, addr1, addr2,
  //  addr_full, landmark, customer_note, total, paid, pay_method, discount,
  //  delivery_fee, status, driver_state, distance_km, eta_min, sla_minutes,
  //  lat, lng, multi_pharmacy, created_at, delivered_at,
  //  items: [{name, quantity, price, tag, pharmacy}]}
  // NOTE: `driver_state` comes back camelCase ("pickedUp"), not snake_case
  // like the /status endpoint expects when SENDING — _driverStateFrom
  // normalizes both forms defensively.
  factory Order.fromJson(Map<String, dynamic> j) {
    final itemsJson = (j['items'] as List?) ?? const [];
    final pickupsJson = (j['pickups'] as List?) ?? const []; // not present in the confirmed /orders response — likely only on order-detail or multi-pharmacy orders
    // TEMP trace — tracing a report of orders showing "paid" in the UI
    // despite backend sending paid:false for that order. Remove once
    // confirmed/fixed. Prints the RAW value exactly as received, before
    // any parsing, so we can see whether the app itself ever actually
    // gets paid:false for the affected order, or something upstream of
    // this constructor already has it wrong.
    debugPrint('[Order.fromJson] id=${j['id'] ?? j['code']} raw j["paid"]=${j['paid']} (type: ${j['paid'].runtimeType})');
    // CLIENT-REPORTED (2026-08-18): confirmed live — order APM36070 had
    // items from two different pharmacies (Pharmaline + Albayrouni) but
    // backend's own multi_pharmacy flag was false. The old fallback here
    // (pickupsJson.length > 1) never actually engaged since pickups is
    // always empty (see comment above) — so the app was entirely at the
    // mercy of a flag we've now seen be wrong. The pharmacies array
    // itself is confirmed-real data; its own length is more reliable
    // than trusting multi_pharmacy alone. This one flag drives several
    // things downstream — showing every item's pharmacy name, routing
    // into the multi-pickup flow, and the pharmacy-pickup summary card —
    // so getting it right here fixes all of those at once rather than
    // needing separate patches for each symptom.
    final pharmaciesList = ((j['pharmacies'] ?? const []) as List)
        .map((e) => Pharmacy.fromJson(e as Map<String, dynamic>))
        .toList();
    return Order(
      id: (j['id'] ?? j['code'] ?? '').toString(),
      co: (j['co_id'] ?? j['co'] ?? j['combined_order_id'])?.toString(),
      stopNumber: j['stop_number'] ?? j['stopNumber'] ?? 1,
      patient: j['patient'] ?? '',
      phone: j['phone'] ?? j['phone_intl'] ?? '',
      addr1: j['addr1'] ?? '',
      addr2: j['addr2'] ?? '',
      landmark: j['landmark'],
      customerNote: j['customer_note'],
      items: itemsJson.map((e) => OrderItem.fromJson(e)).toList(),
      total: (j['total'] ?? 0).toDouble(),
      paid: j['paid'] ?? false,
      payMethod: _payMethodFrom(j['pay_method']),
      discount: (j['discount'] as num?)?.toDouble(),
      deliveryFee: (j['delivery_fee'] as num?)?.toDouble(),
      status: _resolveStatus(j),
      driverState: _driverStateFrom(j['driver_state']),
      distanceKm: (j['distance_km'] as num? ?? 0).toDouble(),
      etaMin: j['eta_min'] ?? 0,
      pinPos: j['lat'] != null && j['lng'] != null
          ? PinPos((j['lng'] as num).toDouble(), (j['lat'] as num).toDouble())
          : const PinPos(0.5, 0.5),
      // CONFIRMED LIVE (2026-08-11): real field name is "map_link".
      pharmacies: pharmaciesList,
      mapLink: (j['map_link'] as String?)?.trim().isNotEmpty == true ? j['map_link'] as String : null,
      paymentLink: (j['payment_link'] as String?)?.trim().isNotEmpty == true ? j['payment_link'] as String : null,
      transactionId: j['transaction_id']?.toString(),
      multiPharmacy: j['multi_pharmacy'] == true || pharmaciesList.length > 1,
      pharmaciesPicked: j['pharmacies_picked'] is int ? j['pharmacies_picked'] as int : int.tryParse('${j['pharmacies_picked']}'),
      pharmaciesTotal: j['pharmacies_total'] is int ? j['pharmacies_total'] as int : int.tryParse('${j['pharmacies_total']}'),
      pickups: pickupsJson.map((e) => PharmacyPickup.fromJson(e)).toList(),
      deliveredAt: _parseDate(j['delivered_at']),
      failureReason: j['failure_reason'],
      createdAt: _parseDate(j['created_at']),
      slaMinutes: j['sla_minutes'] ?? 30,
    );
  }

  // Backend sends "2026-07-06 16:57:41" (space, not 'T') — normalize before parsing.
  static DateTime? _parseDate(String? s) =>
      s == null ? null : DateTime.tryParse(s.replaceFirst(' ', 'T'));

  // CLIENT-REPORTED (2026-08-13): confirmed live — backend exposes a
  // SEPARATE `driver_order_status` field specifically for queue position
  // (active/next/later/batch_pending), distinct from `status` (the
  // order's own delivery outcome). Proof: a real response had one order
  // with `"status":"failed"` (delivery failed) while STILL showing
  // `"driver_order_status":"active"` — a failed order can't genuinely be
  // "active" in the queue sense, so these are two independent fields,
  // and driver_order_status is presumably just never cleared once an
  // order fails. This matters because POST /orders/{co}/position (the
  // reorder endpoint) evidently updates driver_order_status specifically
  // — a successful reorder was reverting on the very next refresh
  // because the model only ever read `status`, which that endpoint never
  // touches at all.
  static OrderStatus _resolveStatus(Map<String, dynamic> j) {
    final rawStatus = j['status'] as String?;
    // done/delivered/failed are delivery OUTCOMES, not queue positions —
    // always authoritative from `status` regardless of driver_order_status.
    if (rawStatus == 'done' || rawStatus == 'delivered' || rawStatus == 'failed') {
      return _statusFrom(rawStatus);
    }
    // Otherwise (queue position: active/next/later/batch_pending), prefer
    // the dedicated driver_order_status field when present.
    final rawDriverOrderStatus = j['driver_order_status'] as String?;
    return _statusFrom(rawDriverOrderStatus ?? rawStatus);
  }

  static OrderStatus _statusFrom(String? s) {
    switch (s) {
      case 'next': return OrderStatus.next;
      case 'later': return OrderStatus.later;
      case 'done': case 'delivered': return OrderStatus.done;
      case 'failed': return OrderStatus.failed;
      case 'batch_pending': case 'batchPending': return OrderStatus.batchPending;
      default: return OrderStatus.active;
    }
  }

  // Normalizes away case/underscore differences — CONFIRMED the API sends
  // "pickedUp" (camelCase) for driver_state on read, even though the write
  // side (/orders/{co}/status) expects snake_case ('picked_up').
  static DriverState _driverStateFrom(String? s) {
    final norm = (s ?? '').replaceAll('_', '').toLowerCase();
    switch (norm) {
      case 'collecting': return DriverState.collecting;
      case 'pickedup': return DriverState.pickedUp;
      case 'onmyway': case 'ontheway': return DriverState.onMyWay;
      case 'delivered': return DriverState.delivered;
      case 'failed': return DriverState.failed;
      default: return DriverState.pending;
    }
  }

  static PayMethod _payMethodFrom(String? s) {
    switch (s) {
      case 'knet': return PayMethod.knet;
      case 'online': return PayMethod.online;
      case 'link': return PayMethod.link;
      default: return PayMethod.cash;
    }
  }
}

// ── Driver / User profile ──────────────────────────────────────
class DriverProfile {
  final int? id;
  final String name;
  final String phone;
  final String avatarInitials;
  final String? vehiclePlate;
  bool onShift;
  VehicleType vehicleType;
  String plateNumber;
  double todayEarnings;
  int deliveriesToday;
  double rating;
  bool needsVehicle; // CONFIRMED field from /me — true means force the vehicle-setup screen
  String? language; // CONFIRMED field from /me — the driver's saved language ('en'/'ar')
  DateTime? shiftStartedAt; // CONFIRMED field from /me — was never parsed before despite being in the response
  // NOT confirmed whether /me returns this yet (only confirmed source so
  // far is the upload response itself: {"ok":true,"url":"..."}). Parsed
  // defensively here so it starts working for free the moment /me adds
  // it too, without needing another round of changes.
  String? photoUrl;

  DriverProfile({
    this.id,
    required this.name,
    required this.phone,
    required this.avatarInitials,
    this.vehiclePlate,
    this.onShift = false,
    this.vehicleType = VehicleType.motorbike,
    this.plateNumber = '',
    this.todayEarnings = 0.0,
    this.deliveriesToday = 0,
    this.rating = 4.9,
    this.needsVehicle = false,
    this.language,
    this.shiftStartedAt,
    this.photoUrl,
  });

  // CONFIRMED shape (seen live): {"id", "name", "phone", "vehicle_type",
  // "plate_number", "language", "needs_vehicle", "is_online" (0/1 int),
  // "shift_started_at"}. NOTE: no earnings/deliveries/rating fields here —
  // those come from GET /earnings instead (still unconfirmed shape there).
  factory DriverProfile.fromApiMe(Map<String, dynamic> j) {
    final name = j['name'] ?? '';
    return DriverProfile(
      id: j['id'],
      name: name,
      phone: j['phone'] ?? '',
      avatarInitials: _initials(name),
      vehiclePlate: j['plate_number'],
      onShift: j['is_online'] == 1 || j['is_online'] == true,
      vehicleType: _vehicleFrom(j['vehicle_type']),
      plateNumber: j['plate_number'] ?? '',
      needsVehicle: j['needs_vehicle'] == true,
      language: j['language'],
      // Was confirmed present in this response but never actually parsed —
      // the Earnings screen's "Work & Hours" section used a hardcoded
      // fake offset (now.subtract(4h22m)) instead of this real value.
      shiftStartedAt: j['shift_started_at'] != null ? DateTime.tryParse(j['shift_started_at']) : null,
      // Unconfirmed whether /me includes this — defensive guess at a few
      // plausible key names. Confirmed-working source is still the
      // upload response's own "url" field, applied optimistically right
      // after a successful upload (see profile_screens.dart).
      photoUrl: j['photo_url'] ?? j['photo'] ?? j['profile_photo'],
      // Not present in /me — left at defaults until GET /earnings is wired
      // into the profile refresh, or confirmed to live elsewhere.
      todayEarnings: 0.0,
      deliveriesToday: 0,
      rating: 4.9,
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static VehicleType _vehicleFrom(String? s) {
    switch (s) {
      case 'car': return VehicleType.car;
      case 'scooter': return VehicleType.scooter;
      default: return VehicleType.motorbike;
    }
  }
}

// ── Batch ──────────────────────────────────────────────────────
class Batch {
  final String? id; // batch_id for POST /batch/{batch_id}/accept|reject — confirm key name in GET /batch response
  final String pharmacyName;
  final String pharmacyAddr;
  final double totalDistance;
  final double totalEarning;
  final List<Order> orders;
  Map<String, bool> pickedUp; // orderId → picked
  final Map<String, dynamic>? rawSummary;         // raw "summary" from GET /batch|/pickup — shape unconfirmed
  final List<Map<String, dynamic>>? rawPharmacyStops; // raw "pharmacy_stops" — shape unconfirmed

  Batch({
    this.id,
    required this.pharmacyName,
    required this.pharmacyAddr,
    required this.totalDistance,
    required this.totalEarning,
    required this.orders,
    Map<String, bool>? pickedUp,
    this.rawSummary,
    this.rawPharmacyStops,
  }) : pickedUp = pickedUp ?? {};

  /// CONFIRMED v2 top-level shape from GET /batch and GET /pickup:
  /// {"batch": {...}, "stops": [...], "summary": {...}, "pharmacy_stops": [...]}
  /// Only the top-level keys are confirmed — field names *inside* each of
  /// those four are still a guess. `summary` and `pharmacy_stops` are kept
  /// raw (not force-fit into this model) so screens can read whatever
  /// fields actually come back without another guessed factory here.
  factory Batch.fromApiResponse(Map<String, dynamic> res) {
    final batchJson = (res['batch'] as Map<String, dynamic>?) ?? const {};
    final stopsJson = (res['stops'] as List?) ?? const [];
    return Batch(
      id: (batchJson['batch_id'] ?? batchJson['id'])?.toString(),
      pharmacyName: batchJson['pharmacy_name'] ?? batchJson['pharmacyName'] ?? '',
      pharmacyAddr: batchJson['pharmacy_addr'] ?? batchJson['pharmacyAddr'] ?? '',
      totalDistance: (batchJson['total_distance'] ?? 0).toDouble(),
      totalEarning: (batchJson['total_earning'] ?? 0).toDouble(),
      // Same defensive filter as fetchOrders — skip any stop with no
      // usable id.
      orders: stopsJson.map((e) => Order.fromJson(e)).where((o) => o.id.isNotEmpty).toList(),
      rawSummary: res['summary'] as Map<String, dynamic>?,
      rawPharmacyStops: (res['pharmacy_stops'] as List?)?.cast<Map<String, dynamic>>(),
    );
  }
}
