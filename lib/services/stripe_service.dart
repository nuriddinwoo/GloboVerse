import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_service.dart';

class StripeService extends ChangeNotifier {
  StripeService(this._settings);

  final SettingsService _settings;
  static const _checkoutUrl = String.fromEnvironment('STRIPE_CHECKOUT_URL');

  bool _isReady = false;
  bool _isOpening = false;
  String? _error;

  bool get isReady => _isReady;
  bool get isOpening => _isOpening;
  String? get error => _error;

  Future<void> init() async {
    _isReady = _checkoutUrl.isNotEmpty;
    notifyListeners();
  }

  Future<bool> openCheckout() async {
    if (!_isReady || _isOpening) return false;
    _isOpening = true;
    _error = null;
    notifyListeners();

    try {
      final separator = _checkoutUrl.contains('?') ? '&' : '?';
      final url = Uri.parse(
        '$_checkoutUrl${separator}locale=${_settings.languageCode}',
      );
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) _error = 'Could not open secure checkout.';
      return opened;
    } catch (_) {
      _error = 'Could not open secure checkout.';
      return false;
    } finally {
      _isOpening = false;
      notifyListeners();
    }
  }
}
