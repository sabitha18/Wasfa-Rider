import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../data/repositories/auth_repository.dart';

/// MUST be a top-level (or static) function — firebase_messaging runs this
/// in its own background isolate when a push arrives while the app is
/// backgrounded or fully killed. That isolate has no widget tree / Provider
/// access, so keep this minimal: just enough to log / show a system
/// notification if you later want one for background-only delivery.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[Push] Background message received: ${message.messageId} data=${message.data}');
}

/// Wraps FCM: permission request, token registration with the backend
/// (POST /fcm-token — already implemented in AuthRepository, just never
/// called before now), and foreground message -> local notification +
/// "refresh orders now" signal.
///
/// Call `NotificationService.instance.init()` exactly once, right after
/// the driver is authenticated (session restored OR just logged in) —
/// registering the token requires a valid bearer token to already be set.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _authRepo = AuthRepository();

  /// Fires whenever a push arrives that should trigger an immediate order
  /// refresh, on top of OrdersViewModel's existing 20s polling fallback.
  /// RiderShell subscribes to this and calls OrdersViewModel.refresh().
  final _onNewOrderPushController = StreamController<void>.broadcast();
  Stream<void> get onNewOrderPush => _onNewOrderPushController.stream;

  /// Fires with a specific order ID whenever the driver actually TAPS a
  /// notification (not just receives one) — whether the app was in the
  /// foreground, backgrounded, or fully closed. RiderShell subscribes to
  /// this and navigates straight to that order's detail screen.
  ///
  /// Requires the backend to include the order's ID in the push's DATA
  /// payload (not just title/body) under the key "order_id" — e.g.
  /// { "notification": {...}, "data": { "order_id": "APM10061" } }
  final _onOrderTappedController = StreamController<String>.broadcast();
  Stream<String> get onOrderTapped => _onOrderTappedController.stream;

  static const _channel = AndroidNotificationChannel(
    'high_importance_channel', // must match the manifest's default_notification_channel_id meta-data
    'New orders',
    description: 'Notifies you when a new delivery order is assigned',
    importance: Importance.high,
  );

  bool _initialized = false;

  Future<void> init() async {
    if (!_initialized) {
      _initialized = true;

      // Android 13+ and iOS both require an explicit runtime permission
      // request before any notification will show.
      await _fcm.requestPermission(alert: true, badge: true, sound: true);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        // Fires when the driver taps the local notification we showed
        // ourselves (i.e. a push that arrived while the app was already
        // open in the foreground).
        onDidReceiveNotificationResponse: (details) {
          final orderId = details.payload;
          if (orderId != null && orderId.isNotEmpty) {
            _onOrderTappedController.add(orderId);
          }
        },
      );

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // FCM does NOT auto-show a system notification while the app is in
      // the foreground — do that ourselves, and also refresh orders
      // immediately rather than waiting for the next 20s poll.
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('[Push] Foreground message: ${message.messageId} data=${message.data}');
        _showLocalNotification(message);
        _onNewOrderPushController.add(null);
      });

      // App was backgrounded (not killed) and the driver tapped the system
      // notification to bring it back to the foreground.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('[Push] Notification TAPPED (was backgrounded): ${message.messageId} data=${message.data}');
        _onNewOrderPushController.add(null);
        final orderId = message.data['order_id'];
        if (orderId != null && orderId.isNotEmpty) {
          _onOrderTappedController.add(orderId);
        } else {
          debugPrint('[Push] No "order_id" key in data payload — cannot navigate to a specific order.');
        }
      });

      _fcm.onTokenRefresh.listen((_) => _registerToken());
    }

    // Always re-run, even if already initialized: if a different driver
    // logs into the same device (shared work phone), this re-associates
    // the device's FCM token with whichever driver is now logged in.
    await _registerToken();
  }

  Future<void> _registerToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await _authRepo.registerFcmToken(token);
        debugPrint('[Push] FCM token registered with backend: $token');
      }
    } catch (e) {
      // Non-fatal — driver just won't get pushes until this succeeds on a
      // later app open / token refresh. The 20s polling fallback still covers them.
      debugPrint('[Push] Failed to register FCM token: $e');
    }
  }

  /// Call once at startup (after init()) — checks whether THIS app launch
  /// was caused by tapping a push notification while the app was fully
  /// closed (as opposed to a normal cold start). Safe to call every
  /// startup; only emits if there actually was a launch-causing message.
  Future<void> checkInitialMessage() async {
    final message = await _fcm.getInitialMessage();
    if (message == null) return; // normal cold start, not launched via a notification tap
    debugPrint('[Push] App launched via notification tap (was fully closed): ${message.messageId} data=${message.data}');
    final orderId = message.data['order_id'];
    if (orderId != null && orderId.isNotEmpty) {
      _onOrderTappedController.add(orderId);
    } else {
      debugPrint('[Push] No "order_id" key in data payload — cannot navigate to a specific order.');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? 'New order assigned';
    final body = notification?.body ?? 'You have a new delivery — tap to view.';
    _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'New orders',
          channelDescription: 'Notifies you when a new delivery order is assigned',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: message.data['order_id'], // read back in onDidReceiveNotificationResponse above
    );
  }
}
