import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'data/models/models.dart';
import 'data/repositories/order_repository.dart';
import 'presentation/viewmodels/app_viewmodel.dart';
import 'presentation/viewmodels/orders_viewmodel.dart';
import 'presentation/viewmodels/map_viewmodel.dart';
import 'presentation/screens/auth/auth_screens.dart';
import 'presentation/screens/splash/splash_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/map/in_app_map_screen.dart';
import 'presentation/screens/orders/orders_screen.dart';
import 'presentation/screens/order_detail/order_detail_screen.dart';
import 'presentation/screens/payment/payment_screens.dart';
import 'presentation/screens/batch/batch_screens.dart';
import 'presentation/screens/profile/profile_screens.dart';
import 'presentation/screens/earnings/earnings_screen.dart';
import 'presentation/widgets/shared_widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppViewModel()),
        ChangeNotifierProvider(create: (_) => OrdersViewModel()),
        ChangeNotifierProvider(create: (_) => MapViewModel()),
      ],
      child: const WasfaRiderApp(),
    ),
  );
}

/// Global key so error snackbars can be shown from anywhere (any screen's
/// own Scaffold, or from a ViewModel listener) without needing a
/// BuildContext that's guaranteed to have a Scaffold ancestor.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class WasfaRiderApp extends StatelessWidget {
  const WasfaRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppViewModel>(
      builder: (ctx, appVM, _) => MaterialApp(
        title: kAppName,
        theme: WTheme.theme,
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
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

/// Shows any backend error message as a SnackBar — e.g. "Pick up from all
/// pharmacies first". Call this instead of silently setting `error` and
/// hoping some screen happens to render it.
void showApiErrorSnackbar(String message) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: const Color(0xFFE5484D),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}

// ── Shell: owns the navigation stack as an enum / string ───────
class RiderShell extends StatefulWidget {
  const RiderShell({super.key});

  @override
  State<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<RiderShell> {
  // Phase: 'splash' | 'language' | 'login' | 'otp' | 'vehicle' | 'app'
  String _phase = 'splash';
  // Active screen within 'app'
  String _tab   = 'home';  // home | orders | profile
  String _screen = 'home'; // any sub-screen

  String? _pendingPhone;
  String? _selectedOrderId;
  String? _selectedPhId;
  String? _lastDeliveredId;
  bool _ordersLoaded = false;

  // ── Navigation helpers ──────────────────────────────────────
  void _goTo(String screen) => setState(() => _screen = screen);
  void _changeTab(String tab) => setState(() { _tab = tab; _screen = tab; });
  String? _screenBeforeMap;
  String? _capturedPodPhotoPath;
  void _openMapFor(Order order) => setState(() {
    _screenBeforeMap = _screen;
    _selectedOrderId = order.id;
    _screen = 'map';
  });

  StreamSubscription<void>? _pushRefreshSub;
  StreamSubscription<String>? _orderTapSub;
  String? _dismissedBatchId; // last batch offer the driver already accepted/rejected/let expire

  void _ensureOrdersLoaded() {
    if (_ordersLoaded) return;
    _ordersLoaded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrdersViewModel>().load();
      context.read<OrdersViewModel>().startAutoRefresh(); // silent poll for newly-assigned orders
      context.read<OrdersViewModel>().startBatchPolling(); // tighter, dedicated poll for time-sensitive batch offers
      NotificationService.instance.init(); // requests permission + registers FCM token with backend
      _pushRefreshSub = NotificationService.instance.onNewOrderPush.listen((_) {
        if (mounted) context.read<OrdersViewModel>().refresh();
      });
      _orderTapSub = NotificationService.instance.onOrderTapped.listen(_handleOrderNotificationTap);
      NotificationService.instance.checkInitialMessage(); // was this app launch caused by tapping a push while fully closed?
    });
  }

  /// A push notification for a specific order was tapped (foreground,
  /// backgrounded, or cold-start) — open that order's detail screen the
  /// same way every other "open order" callback in this file does.
  /// Guards against the order not being loaded yet (e.g. a push for a
  /// brand-new assignment arriving before the next poll) by refreshing
  /// first, and fails safe to the Orders tab instead of crashing on a
  /// null order if it still can't be found afterwards.
  Future<void> _handleOrderNotificationTap(String orderId) async {
    final ordersVM = context.read<OrdersViewModel>();
    if (ordersVM.findById(orderId) == null) {
      await ordersVM.refresh();
    }
    if (!mounted) return;
    if (ordersVM.findById(orderId) != null) {
      setState(() { _selectedOrderId = orderId; _screen = 'orderDetail'; });
    } else {
      setState(() { _tab = 'orders'; _screen = 'orders'; });
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text("Couldn't find that order — showing your order list instead"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Wait for the one-time session restore (see main()) then land on the
    // right phase — 'app' if a valid token was found, 'language' otherwise.
    // Splash stays on screen for that whole wait, so there's no flash of
    // the login flow for a driver who's already signed in.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final appVM = context.read<AppViewModel>();
      try {
        await appVM.sessionRestoreFuture;
      } catch (_) {
        // Belt-and-suspenders: whatever went wrong, never let it hang the
        // splash screen forever — fall through to the language/login flow.
      }
      if (!mounted) return;
      setState(() => _phase = appVM.isLoggedIn ? 'app' : 'language');
    });

    // Show ANY backend error message (e.g. "Pick up from all pharmacies
    // first") as a snackbar automatically, from anywhere in the app —
    // no need to wire error display into every individual delivery action.
    // Scoped to OrdersViewModel only: AppViewModel.error already has its
    // own inline red-box display on the login/OTP screens, and clearing
    // it here too would race with that (this listener fires synchronously
    // inside notifyListeners(), before those screens get to rebuild and
    // read the message themselves).
    context.read<OrdersViewModel>().addListener(_showOrdersError);
  }

  void _showOrdersError() {
    final vm = context.read<OrdersViewModel>();
    final msg = vm.error;
    if (msg != null) {
      showApiErrorSnackbar(msg);
      vm.error = null; // consume it so it doesn't repeat on the next rebuild
    }
  }

  @override
  void dispose() {
    context.read<OrdersViewModel>().removeListener(_showOrdersError);
    context.read<OrdersViewModel>().stopAutoRefresh();
    context.read<OrdersViewModel>().stopBatchPolling();
    _pushRefreshSub?.cancel();
    _orderTapSub?.cancel();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Auth flow
    if (_phase == 'splash') return const SplashScreen();
    if (_phase == 'language') return LanguageScreen(onSelected: () => setState(() => _phase = 'login'));
    if (_phase == 'login')    return LoginScreen(onSubmit: (phone) async {
      final ok = await context.read<AppViewModel>().requestOtp(phone);
      if (ok) setState(() { _pendingPhone = phone; _phase = 'otp'; });
    });
    if (_phase == 'otp')      return OtpScreen(phone: _pendingPhone ?? '', onVerified: (code) async {
      final appVM = context.read<AppViewModel>();
      final ok = await appVM.verifyOtp(_pendingPhone ?? '', code);
      if (ok) setState(() => _phase = (appVM.driver?.needsVehicle ?? true) ? 'vehicle' : 'app');
    });
    if (_phase == 'vehicle')  return VehicleSetupScreen(phone: _pendingPhone ?? '', onContinue: () => setState(() => _phase = 'app'));

    // Main app
    _ensureOrdersLoaded();
    // Watching here (not just read) so this rebuilds the instant a new
    // batch offer appears from the 20s poll — the offer has a 15s
    // countdown, so it needs to surface immediately, not wait for some
    // unrelated rebuild to happen to notice it.
    final pendingBatch = context.watch<OrdersViewModel>().pendingBatch;
    final showBatchOffer = pendingBatch != null
        && pendingBatch.id != null
        && pendingBatch.id != _dismissedBatchId;
    return PopScope(
      // Only let the system back button actually exit the app when we're
      // already at a tab's root screen. Otherwise intercept it — this app
      // uses its own custom screen state machine (_screen/_goTo), not
      // Flutter's real Navigator, so most screens are just conditional
      // widget swaps rather than pushed routes. That meant the system
      // back button previously found nothing to pop and just closed the
      // app outright from ANY sub-screen (order detail, payment,
      // signature, etc.) — nothing intercepted it before this.
      canPop: _screen == _tab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goTo(_tab);
      },
      child: Stack(children: [
        _buildAppScreen(),
        if (showBatchOffer)
          BatchIncomingScreen(
            batch: pendingBatch,
            onAccept: () => _handleBatchDecision(pendingBatch, accept: true),
            onReject: () => _handleBatchDecision(pendingBatch, accept: false),
          ),
      ]),
    );
  }

  /// Wired to BatchIncomingScreen's accept/reject/auto-timeout — this
  /// screen and the backend calls behind it (acceptPendingBatch /
  /// rejectPendingBatch) already existed as dead code before now; nothing
  /// ever actually showed the offer or let the driver act on it.
  Future<void> _handleBatchDecision(Batch batch, {required bool accept}) async {
    setState(() => _dismissedBatchId = batch.id);
    final ordersVM = context.read<OrdersViewModel>();
    final ok = accept ? await ordersVM.acceptPendingBatch() : await ordersVM.rejectPendingBatch();
    if (!mounted) return;
    if (accept) {
      showWToast(context, ok ? '📦 Batch accepted — added to your stops' : "Couldn't accept the batch — please try again");
    }
  }

  Widget _buildAppScreen() {
    final ordersVM = context.read<OrdersViewModel>();

    switch (_screen) {
    // ── HOME ─────────────────────────────────────────────────
      case 'home':
        return HomeScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onOpenMap: _openMapFor,
          onArrive: (id) {
            final order = ordersVM.findById(id);
            setState(() {
              _selectedOrderId = id;
              // URGENT FIX (client-reported): a cash order must NEVER skip
              // straight to photo/signature just because order.paid says
              // true — paid alone only means "already settled online"
              // (knet/link), which is trustworthy from backend. Cash can
              // ONLY be confirmed by the driver physically collecting it
              // via CashAmountScreen — the paid flag being (correctly or
              // incorrectly) true must never bypass that for a cash order.
              final canSkipPayment = order != null && order.paid && order.payMethod != PayMethod.cash;
              _screen = canSkipPayment ? 'photo' : 'payment';
            });
          },
        );

    // ── IN-APP MAP ───────────────────────────────────────────
      case 'map':
        final mapOrder = ordersVM.findById(_selectedOrderId ?? '');
        if (mapOrder == null) return HomeScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onOpenMap: _openMapFor,
          onArrive: (id) => setState(() => _screen = 'home'),
        );
        return InAppMapScreen(
          order: mapOrder,
          onBack: () => _goTo(_screenBeforeMap ?? 'home'),
        );

    // ── ORDERS ───────────────────────────────────────────────
      case 'orders':
        return OrdersScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onOpenBatchPickup: () => _goTo('batchPickup'),
          onOpenMap: _openMapFor,
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
          onOpenMap: _openMapFor,
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
          onCaptured: (path) {
            _capturedPodPhotoPath = path;
            _goTo('signature');
          },
        );

      case 'signature':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return SignatureScreen(
          order: order,
          onBack: () => _goTo('photo'),
          onSigned: (signatureBase64) {
            final methodStr = OrderRepository.methodForOrder(order);
            final photoPath = _capturedPodPhotoPath;
            if (photoPath == null) {
              // Shouldn't happen (photo step is required before this one),
              // but guard rather than silently sending finish() without the
              // now-required pod_photo and getting a confusing 422 back.
              showApiErrorSnackbar("Photo wasn't captured — please retake it.");
              _goTo('photo');
              return;
            }
            ordersVM.markDelivered(order.id, payMethod: methodStr, podPhotoPath: photoPath, signatureBase64: signatureBase64);
            context.read<AppViewModel>().addEarnings(order.total * 0.15);
            _lastDeliveredId = order.id;
            _capturedPodPhotoPath = null;
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
            context.read<OrdersViewModel>().stopAutoRefresh();
            context.read<OrdersViewModel>().stopBatchPolling();
            _pushRefreshSub?.cancel();
            _pushRefreshSub = null;
            _orderTapSub?.cancel();
            _orderTapSub = null;
            _ordersLoaded = false;
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
          onOpenMap: _openMapFor,
          onArrive: (id) {
            final order = ordersVM2.findById(id);
            setState(() {
              _selectedOrderId = id;
              // Same urgent fix as the other onArrive above — see comment there.
              final canSkipPayment = order != null && order.paid && order.payMethod != PayMethod.cash;
              _screen = canSkipPayment ? 'photo' : 'payment';
            });
          },
        );
    }
  }
}
