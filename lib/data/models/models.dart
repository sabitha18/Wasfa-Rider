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

// ── Cash handover (Company Cash tab) — backend not built yet ────
// Shapes below are best guesses matching this app's naming conventions;
// treat as unconfirmed until actually hit against a real response.
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
  final double amount;
  final bool isBank;
  final String dateLabel;
  final String? confirmedBy;
  final bool pending;

  const CashHandoverRecord({
    required this.amount,
    required this.isBank,
    required this.dateLabel,
    this.confirmedBy,
    this.pending = false,
  });

  factory CashHandoverRecord.fromJson(Map<String, dynamic> j) => CashHandoverRecord(
    amount: (j['amount'] ?? 0).toDouble(),
    isBank: (j['method'] ?? '') == 'bank',
    dateLabel: (j['date'] ?? j['created_at'] ?? '').toString(),
    confirmedBy: j['confirmed_by'],
    pending: (j['status'] ?? '') == 'pending',
  );
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
  final bool multiPharmacy;
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
    this.multiPharmacy = false,
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
    OrderStatus? status,
    DriverState? driverState,
    DateTime? deliveredAt,
    String? failureReason,
    CallRequest? callRequest,
    CallEscalation? callEscalation,
    List<PharmacyPickup>? pickups,
  }) {
    return Order(
      id: id, co: co, stopNumber: stopNumber, patient: patient, phone: phone,
      addr1: addr1, addr2: addr2, landmark: landmark, customerNote: customerNote,
      items: items, total: total, paid: paid, payMethod: payMethod,
      discount: discount, deliveryFee: deliveryFee,
      status: status ?? this.status,
      driverState: driverState ?? this.driverState,
      distanceKm: distanceKm, etaMin: etaMin, pinPos: pinPos,
      multiPharmacy: multiPharmacy,
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
      status: _statusFrom(j['status']),
      driverState: _driverStateFrom(j['driver_state']),
      distanceKm: (j['distance_km'] as num? ?? 0).toDouble(),
      etaMin: j['eta_min'] ?? 0,
      pinPos: j['lat'] != null && j['lng'] != null
          ? PinPos((j['lng'] as num).toDouble(), (j['lat'] as num).toDouble())
          : const PinPos(0.5, 0.5),
      multiPharmacy: j['multi_pharmacy'] ?? pickupsJson.length > 1,
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
