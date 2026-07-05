/// Named routes used throughout the app.
class AppRoutes {
  AppRoutes._();
  static const String splash        = '/';
  static const String language      = '/language';
  static const String login         = '/login';
  static const String otp           = '/otp';
  static const String vehicle       = '/vehicle';
  static const String home          = '/home';
  static const String orders        = '/orders';
  static const String orderDetail   = '/order-detail';
  static const String batchPickup   = '/batch-pickup';
  static const String multiPickup   = '/multi-pickup';
  static const String pharmacyStop  = '/pharmacy-stop';
  static const String payment       = '/payment';
  static const String cashAmount    = '/cash-amount';
  static const String sendLink      = '/send-link';
  static const String photo         = '/photo';
  static const String signature     = '/signature';
  static const String success       = '/success';
  static const String failed        = '/failed';
  static const String callEscalation = '/call-escalation';
  static const String profile       = '/profile';
  static const String history       = '/history';
}

/// Google Maps API key — replace with your key from Google Cloud Console.
/// Enable: Maps SDK for Android/iOS + Directions API
const String kGoogleMapsApiKey = 'AIzaSyCwasrWlCcRar6hb9WidlEKIU9ye62pBjg';

/// App-level misc
const String kAppName = 'WASFA Rider';
const String kCurrency = 'KD';
