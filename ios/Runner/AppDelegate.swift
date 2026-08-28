import UIKit
import Flutter
import GoogleMaps
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Google Maps SDK with your API key
    // The key is also in Info.plist as GMSApiKey
    GMSServices.provideAPIKey("AIzaSyCwasrWlCcRar6hb9WidlEKIU9ye62pBjg")

    // CLIENT-REPORTED (2026-08-27): a push notification for a newly
    // assigned order never appeared on iOS. This was missing entirely —
    // it's Firebase's own recommended pattern for ensuring iOS
    // correctly routes notification delegate callbacks (including
    // whether to present a notification while the app is in the
    // foreground) through to the FCM plugin layer. FirebaseApp.configure()
    // itself is already handled automatically by the firebase_core
    // plugin via GeneratedPluginRegistrant below, so it's not added
    // again here — only this delegate assignment was missing.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
