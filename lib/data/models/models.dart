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

  const OrderItem({
    required this.name,
    required this.price,
    this.qty = 1,
    this.color = const Color(0xFFE8646A),
    this.tag = 'Rx',
    this.pharmacy,
  });
}

// ── Pharmacy Pickup (multi-pharmacy orders) ────────────────────
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
  final String id;
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
      id: id, stopNumber: stopNumber, patient: patient, phone: phone,
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
}

// ── Driver / User profile ──────────────────────────────────────
class DriverProfile {
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

  DriverProfile({
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
  });
}

// ── Batch ──────────────────────────────────────────────────────
class Batch {
  final String pharmacyName;
  final String pharmacyAddr;
  final double totalDistance;
  final double totalEarning;
  final List<Order> orders;
  Map<String, bool> pickedUp; // orderId → picked

  Batch({
    required this.pharmacyName,
    required this.pharmacyAddr,
    required this.totalDistance,
    required this.totalEarning,
    required this.orders,
    Map<String, bool>? pickedUp,
  }) : pickedUp = pickedUp ?? {};
}
