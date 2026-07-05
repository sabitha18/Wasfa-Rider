import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/models/models.dart';
import 'presentation/viewmodels/app_viewmodel.dart';
import 'presentation/viewmodels/orders_viewmodel.dart';
import 'presentation/viewmodels/map_viewmodel.dart';
import 'presentation/screens/auth/auth_screens.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/orders/orders_screen.dart';
import 'presentation/screens/order_detail/order_detail_screen.dart';
import 'presentation/screens/payment/payment_screens.dart';
import 'presentation/screens/batch/batch_screens.dart';
import 'presentation/screens/profile/profile_screens.dart';
import 'presentation/screens/earnings/earnings_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppViewModel()),
        ChangeNotifierProvider(create: (_) => OrdersViewModel()..init()),
        ChangeNotifierProvider(create: (_) => MapViewModel()),
      ],
      child: const WasfaRiderApp(),
    ),
  );
}

class WasfaRiderApp extends StatelessWidget {
  const WasfaRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppViewModel>(
      builder: (ctx, appVM, _) => MaterialApp(
        title: kAppName,
        theme: WTheme.theme,
        debugShowCheckedModeBanner: false,
        // Directionality from language
        builder: (ctx, child) => Directionality(
          textDirection: appVM.isRTL ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: const RiderShell(),
      ),
    );
  }
}

// ── Shell: owns the navigation stack as an enum / string ───────
class RiderShell extends StatefulWidget {
  const RiderShell({super.key});

  @override
  State<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<RiderShell> {
  // Phase: 'splash' | 'language' | 'login' | 'otp' | 'vehicle' | 'app'
  String _phase = 'language';
  // Active screen within 'app'
  String _tab   = 'home';  // home | orders | profile
  String _screen = 'home'; // any sub-screen

  String? _pendingPhone;
  String? _selectedOrderId;
  String? _selectedPhId;
  String? _lastDeliveredId;

  // ── Navigation helpers ──────────────────────────────────────
  void _goTo(String screen) => setState(() => _screen = screen);
  void _changeTab(String tab) => setState(() { _tab = tab; _screen = tab; });

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Auth flow
    if (_phase == 'language') return LanguageScreen(onSelected: () => setState(() => _phase = 'login'));
    if (_phase == 'login')    return LoginScreen(onSubmit: (phone) => setState(() { _pendingPhone = phone; _phase = 'otp'; }));
    if (_phase == 'otp')      return OtpScreen(phone: _pendingPhone ?? '', onVerified: () => setState(() => _phase = 'vehicle'));
    if (_phase == 'vehicle')  return VehicleSetupScreen(phone: _pendingPhone ?? '', onContinue: () => setState(() => _phase = 'app'));

    // Main app
    return _buildAppScreen();
  }

  Widget _buildAppScreen() {
    final ordersVM = context.read<OrdersViewModel>();

    switch (_screen) {
    // ── HOME ─────────────────────────────────────────────────
      case 'home':
        return HomeScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onArrive: (id) {
            final order = ordersVM.findById(id);
            setState(() {
              _selectedOrderId = id;
              if (order == null || order.paid) {
                _screen = 'photo'; // already paid — skip to photo POD
              } else {
                _screen = 'payment'; // needs payment first
              }
            });
          },
        );

    // ── ORDERS ───────────────────────────────────────────────
      case 'orders':
        return OrdersScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onOpenBatchPickup: () => _goTo('batchPickup'),
          onCallNow: (id) {
            ordersVM.acceptCallRequest(id);
            setState(() { _selectedOrderId = id; _screen = 'orderDetail'; });
          },
        );

    // ── ORDER DETAIL ──────────────────────────────────────────
      case 'orderDetail':
        final orderId = _selectedOrderId ?? '';
        return OrderDetailScreen(
          orderId: orderId,
          onBack: () => _goTo(_tab),
          onArrive: () => _goTo('payment'),
          onCantDeliver: () => _goTo('failedDelivery'),
          onTransitionState: (id, state) => ordersVM.transitionDriverState(id, state as DriverState),
          onMultiPickup: () => _goTo('multiPickup'),
        );

    // ── PAYMENT ───────────────────────────────────────────────
      case 'payment':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return PaymentScreen(
          order: order,
          onBack: () => _goTo('orderDetail'),
          onCollectCash: () => _goTo('cashAmount'),        // cash → enter amount
          onCollectKnet: () => _goTo('photo'),             // knet → straight to photo
          onSendLink: () => _goTo('sendLink'),             // link → send link screen
        );

      case 'cashAmount':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return CashAmountScreen(
          order: order,
          onBack: () => _goTo('payment'),
          onConfirm: (_) => _goTo('photo'),               // cash confirmed → photo
        );

      case 'sendLink':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return SendLinkScreen(
          order: order,
          onBack: () => _goTo('payment'),
          onSent: () => _goTo('orderDetail'),             // link sent → back to order detail (async payment)
        );

      case 'photo':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return PhotoPODScreen(
          order: order,
          onBack: () => _goTo('payment'),
          onCaptured: () => _goTo('signature'),
        );

      case 'signature':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return SignatureScreen(
          order: order,
          onBack: () => _goTo('photo'),
          onSigned: () {
            ordersVM.markDelivered(order.id);
            context.read<AppViewModel>().addEarnings(order.total * 0.15);
            _lastDeliveredId = order.id;
            _goTo('success');
          },
        );

    // ── SUCCESS ───────────────────────────────────────────────
      case 'success':
        final delivered = ordersVM.findById(_lastDeliveredId ?? '');
        final next = ordersVM.activeOrder;
        return SuccessScreen(
          order: delivered ?? ordersVM.doneOrders.last,
          nextOrder: next,
          earningsBump: (delivered?.total ?? 0) * 0.15,
          onContinue: () => _changeTab('home'),
        );

    // ── FAILED DELIVERY ───────────────────────────────────────
      case 'failedDelivery':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return FailedDeliveryScreen(
          order: order,
          onBack: () => _goTo('orderDetail'),
          onConfirm: (reason) {
            ordersVM.markFailed(order.id, reason);
            _goTo('orders');
          },
        );

    // ── BATCH PICKUP ──────────────────────────────────────────
      case 'batchPickup':
        final batchOrders = ordersVM.batchOrderIds
            .map((id) => ordersVM.findById(id))
            .whereType<Order>()
            .toList();
        return BatchPickupScreen(
          pharmacyName: ordersVM.batchPharmacyName ?? '',
          pharmacyAddr: ordersVM.batchPharmacyAddr ?? '',
          batchOrders: batchOrders,
          pickedUp: ordersVM.batchPickedUp,
          onPick: (id) => ordersVM.markBatchOrderPickedUp(id),
          onStart: () => _goTo('orders'),
          onBack: () => _goTo('orders'),
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
        );

    // ── MULTI-PHARMACY ────────────────────────────────────────
      case 'multiPickup':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return MultiPickupScreen(
          order: order,
          onBack: () => _goTo('orderDetail'),
          onOpenPharmacy: (phId) => setState(() { _selectedPhId = phId; _screen = 'pharmacyStop'; }),
          onReadyToDeliver: () {
            ordersVM.transitionDriverState(order.id, DriverState.pickedUp);
            _goTo('orderDetail');
          },
        );

      case 'pharmacyStop':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return SinglePharmacyStopScreen(
          order: order,
          phId: _selectedPhId ?? '',
          onBack: () => _goTo('multiPickup'),
          onConfirmPickup: () {
            ordersVM.markPharmacyPickedUp(order.id, _selectedPhId ?? '');
            _goTo('multiPickup');
          },
        );

    // ── EARNINGS ──────────────────────────────────────────────
      case 'earnings':
        return EarningsScreen(onTabChange: _changeTab);

    // ── PROFILE ───────────────────────────────────────────────
      case 'profile':
        return ProfileScreen(
          onTabChange: _changeTab,
          onOpenHistory: () => _goTo('history'),
          onLogout: () {
            context.read<AppViewModel>().logout();
            setState(() => _phase = 'language');
          },
        );

      case 'history':
        return HistoryScreen(onBack: () => _goTo('profile'));

      default:
        final ordersVM2 = context.read<OrdersViewModel>();
        return HomeScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onArrive: (id) {
            final order = ordersVM2.findById(id);
            setState(() {
              _selectedOrderId = id;
              _screen = (order == null || order.paid) ? 'photo' : 'payment';
            });
          },
        );
    }
  }
}
