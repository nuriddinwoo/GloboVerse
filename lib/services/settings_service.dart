import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  static const _languageKey = 'language_code';
  static const _displayNameKey = 'display_name';
  static const _onboardingKey = 'onboarding_complete';
  static const _notificationsKey = 'notifications_enabled';
  static const _remainingSecondsKey = 'remaining_seconds';
  static const _vipUntilKey = 'vip_until';
  static const _sessionActiveKey = 'session_active';
  static const _sessionUpdatedAtKey = 'session_updated_at';
  static const _processedPurchasesKey = 'processed_purchases';

  SharedPreferences? _preferences;
  String _languageCode = 'en';
  String _displayName = '';
  bool _onboardingComplete = false;
  bool _notificationsEnabled = true;
  int _remainingSeconds = const Duration(minutes: 20).inSeconds;
  DateTime? _vipUntil;
  bool _sessionWasActive = false;
  DateTime? _sessionUpdatedAt;
  Set<String> _processedPurchases = {};

  String get languageCode => _languageCode;
  String get displayName => _displayName;
  bool get onboardingComplete => _onboardingComplete;
  bool get notificationsEnabled => _notificationsEnabled;
  int get remainingSeconds => _remainingSeconds;
  DateTime? get vipUntil => _vipUntil;
  bool get sessionWasActive => _sessionWasActive;
  DateTime? get sessionUpdatedAt => _sessionUpdatedAt;

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    final deviceLanguage = PlatformDispatcher.instance.locale.languageCode;
    _languageCode = _normalizeLanguageCode(
      _preferences?.getString(_languageKey) ?? deviceLanguage,
    );
    _displayName = _preferences?.getString(_displayNameKey) ?? '';
    _onboardingComplete = _preferences?.getBool(_onboardingKey) ?? false;
    _notificationsEnabled = _preferences?.getBool(_notificationsKey) ?? true;
    _remainingSeconds =
        _preferences?.getInt(_remainingSecondsKey) ??
        const Duration(minutes: 20).inSeconds;
    _sessionWasActive = _preferences?.getBool(_sessionActiveKey) ?? false;
    _processedPurchases =
        (_preferences?.getStringList(_processedPurchasesKey) ??
                const <String>[])
            .toSet();

    final vipMilliseconds = _preferences?.getInt(_vipUntilKey);
    _vipUntil = vipMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(vipMilliseconds);

    final sessionMilliseconds = _preferences?.getInt(_sessionUpdatedAtKey);
    _sessionUpdatedAt = sessionMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sessionMilliseconds);
  }

  Future<void> setLanguageCode(String value) async {
    final normalized = _normalizeLanguageCode(value);
    if (normalized == _languageCode) return;
    _languageCode = normalized;
    notifyListeners();
    await _preferences?.setString(_languageKey, normalized);
  }

  static String _normalizeLanguageCode(String value) {
    final normalized = value.trim().toLowerCase().split(RegExp('[-_]')).first;
    return normalized.isEmpty ? 'en' : normalized;
  }

  Future<void> setDisplayName(String value) async {
    final cleanValue = value.trim();
    if (cleanValue == _displayName) return;
    _displayName = cleanValue;
    notifyListeners();
    await _preferences?.setString(_displayNameKey, cleanValue);
  }

  Future<void> setOnboardingComplete(bool value) async {
    if (value == _onboardingComplete) return;
    _onboardingComplete = value;
    notifyListeners();
    await _preferences?.setBool(_onboardingKey, value);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (value == _notificationsEnabled) return;
    _notificationsEnabled = value;
    notifyListeners();
    await _preferences?.setBool(_notificationsKey, value);
  }

  Future<void> setRemainingSeconds(int value) async {
    final safeValue = value.clamp(0, const Duration(hours: 99).inSeconds);
    _remainingSeconds = safeValue;
    await _preferences?.setInt(_remainingSecondsKey, safeValue);
  }

  Future<void> setVipUntil(DateTime? value) async {
    _vipUntil = value;
    notifyListeners();
    if (value == null) {
      await _preferences?.remove(_vipUntilKey);
    } else {
      await _preferences?.setInt(_vipUntilKey, value.millisecondsSinceEpoch);
    }
  }

  bool hasProcessedPurchase(String purchaseId) {
    return _processedPurchases.contains(purchaseId);
  }

  Future<void> markPurchaseProcessed(String purchaseId) async {
    if (_processedPurchases.add(purchaseId)) {
      await _preferences?.setStringList(
        _processedPurchasesKey,
        _processedPurchases.toList(growable: false),
      );
    }
  }

  Future<void> setSessionState({
    required bool active,
    required DateTime updatedAt,
  }) async {
    _sessionWasActive = active;
    _sessionUpdatedAt = updatedAt;
    await Future.wait([
      _preferences?.setBool(_sessionActiveKey, active) ?? Future.value(true),
      _preferences?.setInt(
            _sessionUpdatedAtKey,
            updatedAt.millisecondsSinceEpoch,
          ) ??
          Future.value(true),
    ]);
  }
}
