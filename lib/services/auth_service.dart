import 'package:flutter/foundation.dart';

import 'settings_service.dart';

class AuthService extends ChangeNotifier {
  AuthService(this._settings) : _isSignedIn = _settings.onboardingComplete;

  final SettingsService _settings;
  bool _isSignedIn;
  bool _isBusy = false;
  String? _error;

  bool get isSignedIn => _isSignedIn;
  bool get isBusy => _isBusy;
  String? get error => _error;
  String get displayName => _settings.displayName;

  Future<bool> completeOnboarding({required String displayName}) async {
    final cleanName = displayName.trim();
    if (cleanName.length < 2) {
      _error = 'Please enter at least two characters.';
      notifyListeners();
      return false;
    }

    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      await _settings.setDisplayName(cleanName);
      await _settings.setOnboardingComplete(true);
      _isSignedIn = true;
      return true;
    } catch (_) {
      _error = 'Could not save your profile. Please try again.';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isBusy = true;
    notifyListeners();
    await _settings.setOnboardingComplete(false);
    _isSignedIn = false;
    _isBusy = false;
    notifyListeners();
  }
}
