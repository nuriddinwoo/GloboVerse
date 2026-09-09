import 'dart:async';

import 'package:flutter/widgets.dart';

import 'settings_service.dart';

class SessionService extends ChangeNotifier with WidgetsBindingObserver {
  SessionService(this._settings)
    : _remaining = Duration(seconds: _settingsSafeSeconds(_settings)) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SettingsService _settings;
  Duration _remaining;
  Timer? _timer;
  DateTime _lastTick = DateTime.now();
  int _ticksSinceSave = 0;
  bool _isActive = false;

  Duration get remaining => _remaining;
  bool get isActive => _isActive;
  bool get isVip => _settings.vipUntil?.isAfter(DateTime.now()) ?? false;
  bool get canStart => isVip || _remaining.inSeconds > 0;

  static int _settingsSafeSeconds(SettingsService settings) {
    return settings.remainingSeconds.clamp(
      0,
      const Duration(hours: 99).inSeconds,
    );
  }

  void refreshVip() {
    final expired = _settings.vipUntil?.isBefore(DateTime.now()) ?? false;
    if (expired) unawaited(_settings.setVipUntil(null));
    notifyListeners();
  }

  void resume() {
    if (!_settings.sessionWasActive) return;
    final now = DateTime.now();
    final lastUpdate = _settings.sessionUpdatedAt;
    if (!isVip && lastUpdate != null) {
      final elapsed = now.difference(lastUpdate);
      if (!elapsed.isNegative) {
        _remaining = Duration(
          seconds: (_remaining.inSeconds - elapsed.inSeconds).clamp(0, 359999),
        );
      }
    }
    start();
  }

  bool start() {
    if (_isActive) return true;
    refreshVip();
    if (!canStart) return false;
    _isActive = true;
    _lastTick = DateTime.now();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    unawaited(_saveState());
    notifyListeners();
    return true;
  }

  void pause() {
    if (!_isActive) return;
    _applyElapsed();
    _isActive = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_saveState());
    notifyListeners();
  }

  void extendBy(Duration duration) {
    if (duration.isNegative || duration == Duration.zero) return;
    _remaining = Duration(
      seconds: (_remaining.inSeconds + duration.inSeconds).clamp(0, 359999),
    );
    unawaited(_settings.setRemainingSeconds(_remaining.inSeconds));
    notifyListeners();
  }

  Future<void> grantVip(Duration duration) async {
    final now = DateTime.now();
    final currentExpiry = _settings.vipUntil;
    final startsAt = currentExpiry != null && currentExpiry.isAfter(now)
        ? currentExpiry
        : now;
    await _settings.setVipUntil(startsAt.add(duration));
    notifyListeners();
  }

  void _onTick() {
    if (!_isActive) return;
    _applyElapsed();
    _ticksSinceSave += 1;
    if (_ticksSinceSave >= 5) {
      _ticksSinceSave = 0;
      unawaited(_saveState());
    }
    notifyListeners();
  }

  void _applyElapsed() {
    final now = DateTime.now();
    if (!isVip) {
      final elapsed = now.difference(_lastTick).inSeconds;
      if (elapsed > 0) {
        _remaining = Duration(
          seconds: (_remaining.inSeconds - elapsed).clamp(0, 359999),
        );
      }
      if (_remaining == Duration.zero) {
        _isActive = false;
        _timer?.cancel();
        _timer = null;
      }
    }
    _lastTick = now;
  }

  Future<void> _saveState() async {
    final now = DateTime.now();
    await _settings.setRemainingSeconds(_remaining.inSeconds);
    await _settings.setSessionState(active: _isActive, updatedAt: now);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_isActive) {
        _applyElapsed();
        unawaited(_saveState());
      }
    } else if (state == AppLifecycleState.resumed && _isActive) {
      _applyElapsed();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
