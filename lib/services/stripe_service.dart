import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_service.dart';

/// Dormant HTTPS checkout launcher. Keep it out of purchase UI until verified
/// Stripe webhooks update the authenticated snapshots consumed by the app.
class StripeService extends ChangeNotifier {
  StripeService(this._settings);

  final SettingsService _settings;
  static const _checkoutUrl = String.fromEnvironment('STRIPE_CHECKOUT_URL');

  bool _isReady = false;
  bool _isOpening = false;
  Uri? _checkoutUri;
  String? _error;

  bool get isReady => _isReady;
  bool get isOpening => _isOpening;
  String? get error => _error;

  Future<void> init() async {
    final candidate = Uri.tryParse(_checkoutUrl);
    if (candidate != null &&
        candidate.scheme == 'https' &&
        candidate.hasAuthority &&
        candidate.host.isNotEmpty &&
        candidate.userInfo.isEmpty &&
        !candidate.hasFragment) {
      _checkoutUri = candidate;
      _isReady = true;
    } else {
      _checkoutUri = null;
      _isReady = false;
    }
    notifyListeners();
  }

  Future<bool> openCheckout() async {
    if (!_isReady || _isOpening) return false;
    _isOpening = true;
    _error = null;
    notifyListeners();

    try {
      final checkoutUri = _checkoutUri!;
      final url = checkoutUri.replace(
        queryParameters: {
          ...checkoutUri.queryParameters,
          'locale': _settings.languageCode,
        },
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
