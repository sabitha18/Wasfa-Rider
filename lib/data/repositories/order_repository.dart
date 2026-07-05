import 'package:flutter/material.dart';
import '../models/models.dart';

/// Mock data — mirrors the HTML prototype's SEED_ORDERS and SEED_BATCH.
class OrderRepository {
  static List<Order> seedOrders() {
    final now = DateTime.now();
    return [
      Order(
        id: 'APM10061', stopNumber: 1,
        patient: 'Fatima A.', phone: '+965 9XXX XX42',
        addr1: 'Salmiya · Block 10', addr2: 'St. 5 · House 22',
        landmark: 'Behind Sultan Center',
        customerNote: 'Please do NOT ring the bell — baby sleeping. Knock softly or call when at door.',
        items: [
          OrderItem(name: 'Panadol Extra 24×500mg', price: 1.250, qty: 1,
              color: const Color(0xFFE8646A), tag: 'OTC', pharmacy: 'Al-Salam Pharmacy'),
          OrderItem(name: 'Ventolin Inhaler', price: 2.500, qty: 1,
              color: const Color(0xFF4299E1), tag: 'Rx', pharmacy: 'Al-Salam Pharmacy'),
          OrderItem(name: 'Vitamin D 1000IU', price: 0.500, qty: 1,
              color: const Color(0xFFF6AD55), tag: 'OTC', pharmacy: 'Al-Salam Pharmacy'),
        ],
        total: 4.250, paid: false, payMethod: PayMethod.cash,
        discount: 0.500, deliveryFee: 1.500,
        status: OrderStatus.active, driverState: DriverState.onMyWay,
        distanceKm: 1.2, etaMin: 6,
        pinPos: const PinPos(0.60, 0.40),
        createdAt: now.subtract(const Duration(minutes: 18)),
      ),
      Order(
        id: 'APM10062', stopNumber: 2,
        patient: 'Mohammed H.', phone: '+965 9XXX XX73',
        addr1: 'Hawalli · Tunis St', addr2: 'Bldg 14 · Apt 7',
        landmark: 'Near Tunis Roundabout',
        items: [
          OrderItem(name: 'Lipitor 20mg', price: 6.400, qty: 1,
              color: const Color(0xFF38B2AC), tag: 'Rx', pharmacy: 'Gulf Pharmacy'),
          OrderItem(name: 'Concor 5mg', price: 5.900, qty: 1,
              color: const Color(0xFF667EEA), tag: 'Rx', pharmacy: 'Gulf Pharmacy'),
        ],
        total: 12.800, paid: true, payMethod: PayMethod.online,
        status: OrderStatus.next, driverState: DriverState.pickedUp,
        distanceKm: 3.4, etaMin: 14,
        pinPos: const PinPos(0.75, 0.28),
        createdAt: now.subtract(const Duration(minutes: 22)),
        callRequest: CallRequest(
          from: 'dispatcher', by: 'Saud Q.',
          at: now.subtract(const Duration(minutes: 3)),
          note: 'Patient called — wants to add Vitamin C to the order',
        ),
      ),
      Order(
        id: 'APM10063', stopNumber: 3,
        patient: 'Layla M.', phone: '+965 9XXX XX91',
        addr1: 'Jabriya · Block 4', addr2: 'Eastern Ring Rd',
        landmark: 'Across from Co-op',
        items: [
          OrderItem(name: 'Insulin glargine 100u', price: 4.800, qty: 1,
              color: const Color(0xFF48BB78), tag: 'Rx', pharmacy: 'Al-Noor Pharmacy'),
          OrderItem(name: 'Test strips 50ct', price: 2.100, qty: 1,
              color: const Color(0xFFED8936), tag: 'D2', pharmacy: 'Al-Noor Pharmacy'),
          OrderItem(name: 'Lancets 100ct', price: 0.700, qty: 1,
              color: const Color(0xFF9F7AEA), tag: 'OTC', pharmacy: 'Al-Noor Pharmacy'),
        ],
        total: 7.600, paid: false, payMethod: PayMethod.knet,
        status: OrderStatus.later, driverState: DriverState.pending,
        distanceKm: 5.1, etaMin: 20,
        pinPos: const PinPos(0.80, 0.55),
        createdAt: now.subtract(const Duration(minutes: 10)),
      ),
      Order(
        id: 'APM10059', stopNumber: 1,
        patient: 'Yousef S.', phone: '+965 9XXX XX12',
        addr1: 'Salwa · Block 6', addr2: 'St. 12 · H 4',
        items: [
          OrderItem(name: 'Amoxicillin 500mg', price: 1.500, qty: 2,
              color: const Color(0xFFE8646A), tag: 'Rx', pharmacy: 'Ibn Sina Pharmacy'),
        ],
        total: 3.000, paid: true, payMethod: PayMethod.online,
        status: OrderStatus.done, driverState: DriverState.delivered,
        distanceKm: 0, etaMin: 0,
        pinPos: const PinPos(0.22, 0.18),
        deliveredAt: now.subtract(const Duration(hours: 1, minutes: 16)),
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      Order(
        id: 'APM10080', stopNumber: 6,
        patient: 'Saif K.', phone: '+965 9XXX XX88',
        addr1: 'Salwa · Block 7', addr2: 'St. 3 · House 11',
        landmark: 'Near Salwa Co-op',
        customerNote: 'Leave the order with the security guard at the gate — I am at work.',
        multiPharmacy: true,
        pickups: [
          PharmacyPickup(
            phId: 'ph_alsalam', name: 'Al-Salam Pharmacy', addr: 'Salmiya · Block 1',
            items: ['Panadol Extra 24×500mg', 'Ventolin Inhaler'],
          ),
          PharmacyPickup(
            phId: 'ph_almasarif', name: 'Al-Masaarif Pharmacy', addr: 'Hawalli · Block 5',
            items: ['Insulin glargine 100u', 'Test strips 50ct'],
          ),
          PharmacyPickup(
            phId: 'ph_alnoor', name: 'Al-Noor Pharmacy', addr: 'Jabriya · Block 3',
            items: ['Vitamin D 1000IU', 'Calcium 600mg'],
          ),
        ],
        items: [
          OrderItem(name: 'Panadol Extra 24×500mg', price: 1.250, qty: 1,
              color: const Color(0xFFE8646A), tag: 'OTC', pharmacy: 'Al-Salam Pharmacy'),
          OrderItem(name: 'Ventolin Inhaler', price: 2.500, qty: 1,
              color: const Color(0xFF4299E1), tag: 'Rx', pharmacy: 'Al-Salam Pharmacy'),
          OrderItem(name: 'Insulin glargine 100u', price: 4.800, qty: 2,
              color: const Color(0xFF48BB78), tag: 'Rx', pharmacy: 'Al-Masaarif Pharmacy'),
          OrderItem(name: 'Test strips 50ct', price: 2.100, qty: 1,
              color: const Color(0xFFED8936), tag: 'D2', pharmacy: 'Al-Masaarif Pharmacy'),
          OrderItem(name: 'Vitamin D 1000IU', price: 0.500, qty: 1,
              color: const Color(0xFFF6AD55), tag: 'OTC', pharmacy: 'Al-Noor Pharmacy'),
          OrderItem(name: 'Calcium 600mg', price: 1.100, qty: 1,
              color: const Color(0xFF9F7AEA), tag: 'OTC', pharmacy: 'Al-Noor Pharmacy'),
        ],
        total: 22.500, paid: false, payMethod: PayMethod.cash,
        status: OrderStatus.later, driverState: DriverState.pending,
        distanceKm: 9.2, etaMin: 38,
        pinPos: const PinPos(0.12, 0.85),
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
      Order(
        id: 'APM10060', stopNumber: 2,
        patient: 'Aisha R.', phone: '+965 9XXX XX22',
        addr1: 'Salmiya · Block 7', addr2: 'St. 1 · H 14',
        items: [
          OrderItem(name: 'Multivitamin Adults', price: 4.000, qty: 1,
              color: const Color(0xFF48BB78), tag: 'OTC', pharmacy: 'Ibn Sina Pharmacy'),
        ],
        total: 5.500, paid: false, payMethod: PayMethod.cash,
        status: OrderStatus.done, driverState: DriverState.delivered,
        distanceKm: 0, etaMin: 0,
        pinPos: const PinPos(0.38, 0.28),
        deliveredAt: now.subtract(const Duration(hours: 0, minutes: 54)),
        createdAt: now.subtract(const Duration(hours: 1, minutes: 30)),
      ),
    ];
  }

  static Batch seedBatch() {
    final now = DateTime.now();
    return Batch(
      pharmacyName: 'Al-Salam Pharmacy',
      pharmacyAddr: 'Salmiya · Block 1 · Salem Al-Mubarak St',
      totalDistance: 6.4,
      totalEarning: 3.250,
      orders: [
        Order(
          id: 'APM10071', stopNumber: 1,
          patient: 'Noura A.', phone: '+965 9XXX XX55',
          addr1: 'Salmiya · Block 10', addr2: 'St. 3 · House 8',
          items: [
            OrderItem(name: 'Panadol Extra 24×500mg', price: 1.250, qty: 1,
                color: const Color(0xFFE8646A), tag: 'OTC', pharmacy: 'Al-Salam Pharmacy'),
            OrderItem(name: 'Vitamin C 1000mg', price: 2.500, qty: 1,
                color: const Color(0xFFF6AD55), tag: 'OTC', pharmacy: 'Al-Salam Pharmacy'),
          ],
          total: 4.250, paid: false, payMethod: PayMethod.cash,
          status: OrderStatus.batchPending, driverState: DriverState.pending,
          distanceKm: 1.2, etaMin: 6,
          pinPos: const PinPos(0.55, 0.38),
          createdAt: now.subtract(const Duration(minutes: 8)),
        ),
        Order(
          id: 'APM10072', stopNumber: 2,
          patient: 'Bader K.', phone: '+965 9XXX XX66',
          addr1: 'Salmiya · Block 12', addr2: 'St. 1 · House 22',
          items: [
            OrderItem(name: 'Lipitor 20mg', price: 7.600, qty: 1,
                color: const Color(0xFF38B2AC), tag: 'Rx', pharmacy: 'Al-Salam Pharmacy'),
          ],
          total: 9.100, paid: true, payMethod: PayMethod.online,
          status: OrderStatus.batchPending, driverState: DriverState.pending,
          distanceKm: 2.1, etaMin: 9,
          pinPos: const PinPos(0.68, 0.50),
          createdAt: now.subtract(const Duration(minutes: 8)),
        ),
        Order(
          id: 'APM10073', stopNumber: 3,
          patient: 'Hessa M.', phone: '+965 9XXX XX77',
          addr1: 'Jabriya · Block 4', addr2: 'Eastern Ring Rd',
          items: [
            OrderItem(name: 'Insulin glargine', price: 9.800, qty: 1,
                color: const Color(0xFF48BB78), tag: 'Rx', pharmacy: 'Al-Salam Pharmacy'),
            OrderItem(name: 'Test strips 50ct', price: 4.200, qty: 2,
                color: const Color(0xFFED8936), tag: 'D2', pharmacy: 'Al-Salam Pharmacy'),
            OrderItem(name: 'Lancets 100ct', price: 0.700, qty: 2,
                color: const Color(0xFF9F7AEA), tag: 'OTC', pharmacy: 'Al-Salam Pharmacy'),
          ],
          total: 18.500, paid: false, payMethod: PayMethod.knet,
          status: OrderStatus.batchPending, driverState: DriverState.pending,
          distanceKm: 3.1, etaMin: 14,
          pinPos: const PinPos(0.80, 0.62),
          createdAt: now.subtract(const Duration(minutes: 8)),
        ),
      ],
    );
  }
}
