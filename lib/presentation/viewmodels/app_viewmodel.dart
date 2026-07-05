import 'package:flutter/foundation.dart';
import '../../data/models/models.dart';
import '../../data/repositories/order_repository.dart';

/// Top-level app ViewModel — manages driver session, language, shift toggle.
class AppViewModel extends ChangeNotifier {
  String _language = 'en';
  bool _isLoggedIn = false;
  DriverProfile? _driver;

  String get language => _language;
  bool get isLoggedIn => _isLoggedIn;
  DriverProfile? get driver => _driver;
  bool get isRTL => _language == 'ar';

  void setLanguage(String lang) {
    _language = lang;
    notifyListeners();
  }

  void login(String phone, {VehicleType vehicle = VehicleType.motorbike, String plate = ''}) {
    _driver = DriverProfile(
      name: 'Ahmad K.',
      phone: phone,
      avatarInitials: 'AK',
      vehicleType: vehicle,
      plateNumber: plate,
      onShift: true,
      todayEarnings: 8.750,
      deliveriesToday: 4,
    );
    _isLoggedIn = true;
    notifyListeners();
  }

  void toggleShift() {
    if (_driver != null) {
      _driver!.onShift = !_driver!.onShift;
      notifyListeners();
    }
  }

  void logout() {
    _isLoggedIn = false;
    _driver = null;
    notifyListeners();
  }

  void addEarnings(double amount) {
    if (_driver != null) {
      _driver!.todayEarnings += amount;
      _driver!.deliveriesToday += 1;
      notifyListeners();
    }
  }
}
