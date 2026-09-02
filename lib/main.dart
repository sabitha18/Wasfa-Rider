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

class _RiderShellState extends State<RiderShell> with WidgetsBindingObserver {
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
  // CLIENT-REPORTED (2026-08-18): "amount given" wasn't showing up in the
  // admin dashboard at all. Root cause found here — CashAmountScreen's
  // onConfirm was discarding the entered amount entirely
  // (`onConfirm: (_) => _goTo('photo')`), so by the time finish() ran,
  // there was never a `given` value to send in the first place. Captured
  // now, same pattern as _capturedPodPhotoPath below.
  double? _capturedCashGiven;
  // CLIENT-REPORTED: rider needs to be able to switch payment method at
  // the door (customer changes their mind). PaymentScreen's Cash/KNET
  // taps now record the ACTUAL method chosen here, keyed to the order id
  // so it can never leak onto a different order's flow (e.g. one that
  // skips PaymentScreen entirely because it's already paid online). This
  // is read once at the signature step below and then cleared.
  String? _paymentOverrideOrderId;
  PayMethod? _paymentOverrideMethod;
  // CLIENT-REQUESTED: auto shift on-open/off-close (see
  // didChangeAppLifecycleState below). Captured in didChangeDependencies
  // rather than read fresh wherever needed, same crash-safety reasoning
  // as MapViewModel elsewhere in this app — a lifecycle callback can in
  // principle fire at a point where a fresh context.read() isn't safe.
  AppViewModel? _appVM;
  // CLIENT-REPORTED (2026-08-19): every pharmacy's own "MAP" button
  // opened the map for "the order" generically, which always shows
  // order.primaryPharmacy (always the FIRST pharmacy) regardless of
  // which pharmacy's card was actually tapped. Tracks which specific
  // pharmacy (by seller id) to focus on; cleared when the map is opened
  // generically (e.g. Home's "Maps" button, or the customer's own card).
  int? _focusPharmacySellerId;
  void _openMapFor(Order order) => setState(() {
    _screenBeforeMap = _screen;
    _selectedOrderId = order.id;
    _focusPharmacySellerId = null;
    _screen = 'map';
  });
  void _openMapForPharmacy(Order order, Pharmacy pharmacy) => setState(() {
    _screenBeforeMap = _screen;
    _selectedOrderId = order.id;
    _focusPharmacySellerId = pharmacy.sellerId;
    _screen = 'map';
  });
  // CLIENT-REPORTED (2026-08-19): the multi-pharmacy pickup screen
  // showed "Items to pick up (0)" even for orders that genuinely have
  // items. Root cause: per-pharmacy item NAMES (Pharmacy.itemNames) only
  // exist on the order-detail endpoint's response (GET /orders/{code})
  // — the list endpoint (GET /orders?tab=all), which is what usually
  // populates the order data already sitting in memory when this screen
  // opens, only has a plain items_count number, no nested item list at
  // all. None of this screen's entry points ever called refreshOrder(),
  // so the fuller detail data was never fetched. Centralized here so
  // every entry point gets it, rather than needing the fix repeated at
  // each individual callback.
  void _openMultiPickupFor(String orderId) {
    setState(() { _selectedOrderId = orderId; _screen = 'multiPickup'; });
    context.read<OrdersViewModel>().refreshOrder(orderId);
  }

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
      // CLIENT-REPORTED (2026-08-13): GPS tracking used to start/stop with
      // whichever map screen (Home or InAppMapScreen) happened to be
      // mounted — since tabs fully rebuild rather than staying alive in
      // an IndexedStack, rapid tab-switching meant repeatedly stopping
      // and restarting the native location permission/stream setup,
      // which visibly stalled the UI when triggered many times in quick
      // succession. Started once here for the whole app session instead;
      // only stops on logout (see the logout button below).
      context.read<MapViewModel>().startTracking();
      NotificationService.instance.init(); // requests permission + registers FCM token with backend
      _pushRefreshSub = NotificationService.instance.onNewOrderPush.listen((_) {
        if (mounted) context.read<OrdersViewModel>().refresh(silent: true);
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
      await ordersVM.refresh(silent: true); // already has a graceful fallback below if the order still isn't found
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
    WidgetsBinding.instance.addObserver(this); // for auto shift on-open/off-close below
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
      // CLIENT-REQUESTED: auto-on shift when the app opens. This covers
      // the actual cold-start case — didChangeAppLifecycleState below
      // only fires on lifecycle CHANGES, so it never sees the app's very
      // first launch, only later resumes-from-background.
      if (appVM.isLoggedIn) unawaited(appVM.setShiftAuto(true));
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appVM = context.read<AppViewModel>();
  }

  /// CLIENT-REQUESTED: auto-on shift when the app comes to the
  /// foreground, auto-off when it's backgrounded or closed. `paused` is
  /// backgrounded-but-still-alive (home button, switching apps); `detached`
  /// is the engine actually tearing down (task-swiped away, OS killing
  /// it). Both mean "not in the driver's hands right now" so both turn
  /// shift off. `inactive` (a transient state — e.g. a phone call
  /// interrupting briefly, or a system dialog) is deliberately NOT
  /// treated as "closed" — it's usually momentary, and flipping shift
  /// off for something like an incoming call would be more disruptive
  /// than helpful.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_appVM?.setShiftAuto(true));
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_appVM?.setShiftAuto(false));
      default:
        break;
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
    // CLIENT-REPORTED (2026-08-19): the multi-pharmacy pickup screen kept
    // showing "0 items" even though refreshOrder() was confirmed (via a
    // real order-detail response) to have fetched the correct, complete
    // data. Root cause: this used context.read, not context.watch — read
    // gets the current value once but never subscribes to future
    // changes, so when refreshOrder() finished and called
    // notifyListeners() internally, nothing told this method to rebuild
    // and re-read the now-correct data. The pendingBatch watch just
    // above (in build()) already got this right, with a comment
    // explaining exactly why — this just hadn't been applied here too.
    final ordersVM = context.watch<OrdersViewModel>();

    switch (_screen) {
    // ── HOME ─────────────────────────────────────────────────
      case 'home':
        return HomeScreen(
          onTabChange: _changeTab,
          onOpenOrder: (id) => setState(() { _selectedOrderId = id; _screen = 'orderDetail'; }),
          onOpenMap: _openMapFor,
          onOpenMapForPharmacy: _openMapForPharmacy,
          onTransitionState: (id, state) => ordersVM.transitionDriverState(id, state),
          onMultiPickup: () => _openMultiPickupFor(ordersVM.activeOrder?.id ?? _selectedOrderId ?? ''),
          onArrive: (id) async {
            // CLIENT-REPORTED (2026-08-25): confirmed with a real order
            // (paid: true both in the raw API response and shown
            // correctly elsewhere in the app) that swiping "arrived"
            // still opened the payment screen showing "NOT PAID YET".
            // Root cause: this only ever read whatever was ALREADY
            // cached in memory — if the admin dashboard marks an order
            // paid, that change lives on backend's side until the app's
            // own next scheduled refresh (every 20s) or the driver
            // happens to open Order Detail. Swiping "arrived" in that
            // gap meant deciding based on stale data. The paid-check
            // logic itself was already correct (see the "paid is true
            // then skip" fix above) — this fetches a fresh copy right
            // before making that decision, rather than trusting
            // whatever might be several seconds (or more) out of date.
            await ordersVM.refreshOrder(id);
            final order = ordersVM.findById(id);
            setState(() {
              _selectedOrderId = id;
              final canSkipPayment = order != null && order.paid;
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
          onOpenMapForPharmacy: _openMapForPharmacy,
          onTransitionState: (id, state) => ordersVM.transitionDriverState(id, state),
          onMultiPickup: () => _openMultiPickupFor(ordersVM.activeOrder?.id ?? _selectedOrderId ?? ''),
          onArrive: (id) => setState(() => _screen = 'home'),
        );
        return InAppMapScreen(
          order: mapOrder,
          onBack: () => _goTo(_screenBeforeMap ?? 'home'),
          focusPharmacySellerId: _focusPharmacySellerId,
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
          onOpenMultiPickup: (id) => _openMultiPickupFor(id),
        );

    // ── ORDER DETAIL ──────────────────────────────────────────
      case 'orderDetail':
        final orderId = _selectedOrderId ?? '';
        return OrderDetailScreen(
          orderId: orderId,
          onBack: () => _goTo(_tab),
          // CLIENT-REPORTED (2026-08-25) via video, confirmed with a
          // real order (APM36104, paid:true, pay_method:cash): swiping
          // "arrived" from Order Detail specifically still opened the
          // Collect Payment screen showing "NOT PAID YET" despite the
          // order genuinely being paid. Root cause: this is a
          // completely SEPARATE onArrive callback from HomeScreen's
          // (different signature — plain VoidCallback here vs
          // ValueChanged<String> there) — the earlier fix for this
          // exact "paid should skip straight to photo" behavior was
          // only ever applied to HomeScreen's callback. This one always
          // unconditionally went to 'payment' with no paid check at
          // all. Same fix, same client confirmation ("paid is true
          // then skip", no exception for cash) applied here too.
          onArrive: () async {
            // CLIENT-REPORTED (2026-08-25): same staleness issue as
            // HomeScreen's onArrive above — this only read whatever was
            // already cached, which can be several seconds (or more)
            // out of date if an external system (the admin dashboard)
            // marked the order paid since the app's last refresh.
            // Fetches a fresh copy right before deciding, rather than
            // trusting a potentially stale cache for this decision.
            await ordersVM.refreshOrder(orderId);
            final order = ordersVM.findById(orderId);
            final canSkipPayment = order != null && order.paid;
            _goTo(canSkipPayment ? 'photo' : 'payment');
          },
          onCantDeliver: () => _goTo('failedDelivery'),
          onTransitionState: (id, state) => ordersVM.transitionDriverState(id, state as DriverState),
          onMultiPickup: () => _openMultiPickupFor(orderId),
          onOpenMap: _openMapFor,
          onOpenMapForPharmacy: _openMapForPharmacy,
        );

    // ── PAYMENT ───────────────────────────────────────────────
      case 'payment':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return PaymentScreen(
          order: order,
          onBack: () => _goTo('orderDetail'),
          onCollectCash: () {
            _paymentOverrideOrderId = order.id;
            _paymentOverrideMethod = PayMethod.cash;
            _goTo('cashAmount');        // cash → enter amount
          },
          onCollectKnet: () {
            _paymentOverrideOrderId = order.id;
            _paymentOverrideMethod = PayMethod.knet;
            _goTo('photo');             // knet → straight to photo
          },
          onSendLink: () => _goTo('sendLink'), // link → send link screen (async, doesn't reach signature this session)
        );

      case 'cashAmount':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return CashAmountScreen(
          order: order,
          onBack: () => _goTo('payment'),
          onConfirm: (given) {
            _capturedCashGiven = given;
            _goTo('photo');
          },
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
            // Use whatever the rider actually tapped on PaymentScreen for
            // THIS order, if anything was recorded — otherwise fall back
            // to the order's originally recorded method (covers orders
            // that skip PaymentScreen entirely, e.g. already paid online).
            final methodStr = (_paymentOverrideOrderId == order.id && _paymentOverrideMethod != null)
                ? (_paymentOverrideMethod == PayMethod.knet ? 'knet' : 'cash')
                : OrderRepository.methodForOrder(order);
            _paymentOverrideOrderId = null;
            _paymentOverrideMethod = null;
            final photoPath = _capturedPodPhotoPath;
            if (photoPath == null) {
              // Shouldn't happen (photo step is required before this one),
              // but guard rather than silently sending finish() without the
              // now-required pod_photo and getting a confusing 422 back.
              showApiErrorSnackbar("Photo wasn't captured — please retake it.");
              _goTo('photo');
              return;
            }
            ordersVM.markDelivered(
              order.id,
              payMethod: methodStr,
              podPhotoPath: photoPath,
              signatureBase64: signatureBase64,
              given: _capturedCashGiven?.toStringAsFixed(3),
            );
            context.read<AppViewModel>().addEarnings(order.total * 0.15);
            _lastDeliveredId = order.id;
            _capturedPodPhotoPath = null;
            _capturedCashGiven = null;
            _goTo('success');
          },
        );

    // ── SUCCESS ───────────────────────────────────────────────
      case 'success':
        final delivered = ordersVM.findById(_lastDeliveredId ?? '');
        final next = ordersVM.activeOrder;
        // CLIENT-REQUESTED (2026-09-01): doneOrders (derived from
        // _orders) is always empty now that _orders is sourced from
        // tab=active alone — see OrdersViewModel.load(). findById above
        // already checks _tabOrders as a fallback (so this almost
        // always succeeds anyway, since the order was just active this
        // session), but this last-resort fallback needs its own
        // updated source too. Uses 'all' rather than 'done' — nothing
        // else in the app triggers loadTab('done') anymore (Profile and
        // Earnings both use 'all', for reasons noted in their own
        // initState), so relying on 'done' here would only work by
        // coincidence if the driver happened to have visited the
        // Orders screen first this session.
        final doneFallback = ordersVM.ordersForTab('all').where((o) => o.status == OrderStatus.done).toList();
        return SuccessScreen(
          order: delivered ?? doneFallback.last,
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
          onOpenMapForPharmacy: (pharmacy) => _openMapForPharmacy(order, pharmacy),
        );

      case 'pharmacyStop':
        final order = ordersVM.findById(_selectedOrderId ?? '')!;
        return SinglePharmacyStopScreen(
          order: order,
          sellerKey: _selectedPhId ?? '',
          onBack: () => _goTo('multiPickup'),
          onConfirmPickup: () async {
            Pharmacy? pharmacy;
            for (final p in order.pharmacies) {
              if ('${p.sellerId ?? p.name}' == (_selectedPhId ?? '')) { pharmacy = p; break; }
            }
            if (pharmacy != null) {
              // CLIENT-REPORTED (2026-08-19): this used to update local
              // state and silently swallow any backend failure — the
              // app would show "picked up" even if backend had zero
              // record of it, with nothing telling the driver. Now
              // shows an honest result either way, same pattern as
              // reorderActive's toast.
              final synced = await ordersVM.markPharmacyPickedUp(order.id, pharmacy);
              if (mounted) {
                showWToast(context, synced
                    ? '✅ Pickup confirmed for ${pharmacy.name}'
                    : "⚠️ Marked locally, but couldn't save to the server — it may not persist");
              }
            }
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
            context.read<MapViewModel>().stopTracking(); // tracking now starts once app-wide (see _ensureOrdersLoaded) — stop it here on logout instead of per-screen
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
          onOpenMapForPharmacy: _openMapForPharmacy,
          onTransitionState: (id, state) => ordersVM2.transitionDriverState(id, state),
          onMultiPickup: () => _openMultiPickupFor(ordersVM2.activeOrder?.id ?? _selectedOrderId ?? ''),
          onArrive: (id) async {
            // CLIENT-REPORTED (2026-08-25): same staleness fix as the
            // other two onArrive occurrences — see the first one above
            // for the full explanation.
            await ordersVM2.refreshOrder(id);
            final order = ordersVM2.findById(id);
            setState(() {
              _selectedOrderId = id;
              final canSkipPayment = order != null && order.paid;
              _screen = canSkipPayment ? 'photo' : 'payment';
            });
          },
        );
    }
  }
}
