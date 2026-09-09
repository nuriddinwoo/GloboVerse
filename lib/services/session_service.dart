import 'dart:async';

import 'package:flutter/widgets.dart';

import 'purchase_verification_service.dart';
import 'settings_service.dart';

class SessionService extends ChangeNotifier with WidgetsBindingObserver {
  SessionService(this._settings, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _remaining = Duration(seconds: _settingsSafeSeconds(_settings)),
      _knownVipUntil = _settings.vipUntil {
    _lastTick = _now();
    WidgetsBinding.instance.addObserver(this);
  }

  static const _maximumRemainingSeconds = 99 * 60 * 60;

  final SettingsService _settings;
  final DateTime Function() _now;
  Duration _remaining;
  DateTime? _knownVipUntil;
  Timer? _timer;
  late DateTime _lastTick;
  int _ticksSinceSave = 0;
  bool _isActive = false;

  Duration get remaining => _remaining;
  bool get isActive => _isActive;
  bool get isVip {
    final vipUntil = _knownVipUntil;
    return vipUntil != null && vipUntil.isAfter(_now());
  }

  bool get canStart => isVip || _remaining.inSeconds > 0;

  static int _settingsSafeSeconds(SettingsService settings) {
    return settings.remainingSeconds.clamp(0, _maximumRemainingSeconds);
  }

  void refreshVip() {
    _clearExpiredVip(_now());
    notifyListeners();
  }

  void resume() {
    final now = _now();
    if (!_settings.sessionWasActive) {
      _lastTick = now;
      _clearExpiredVip(now);
      notifyListeners();
      return;
    }

    final lastUpdate = _settings.sessionUpdatedAt;
    if (lastUpdate != null) {
      final storedVipDeadline = _settings.authoritativeVipUntil;
      final expiredVipDeadline =
          storedVipDeadline != null && !storedVipDeadline.isAfter(now)
          ? storedVipDeadline
          : null;
      _consumeElapsed(
        lastUpdate,
        now,
        vipDeadline: _knownVipUntil ?? expiredVipDeadline,
      );
    }
    _lastTick = now;
    _clearExpiredVip(now);
    start();
  }

  bool start() {
    if (_isActive) return true;
    refreshVip();
    if (!canStart) {
      _isActive = false;
      unawaited(_saveState());
      return false;
    }
    _isActive = true;
    _lastTick = _now();
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

  /// Flushes locally consumed time before a trusted grant computes its target.
  Future<void> prepareForVerifiedGrant() async {
    if (_isActive) {
      _applyElapsed();
    } else {
      _lastTick = _now();
    }

    var persisted = await _persistState();
    if (!persisted) {
      await _settings.waitForEntitlementOperations();
      persisted = await _persistState();
    }
    if (!persisted) {
      throw StateError('Could not persist session usage before a grant.');
    }
  }

  /// Merges the trusted post-grant delta with usage since the pre-grant flush.
  Future<void> syncVerifiedPurchaseEntitlements(
    VerifiedPurchaseGrant grant,
    bool wasApplied,
  ) async {
    if (_isActive) {
      _applyElapsed();
    } else {
      _lastTick = _now();
    }
    if (wasApplied && grant.sessionSeconds != null) {
      _remaining = Duration(
        seconds: (_remaining.inSeconds + grant.sessionSeconds!).clamp(
          0,
          _maximumRemainingSeconds,
        ),
      );
    }
    _knownVipUntil = _settings.vipUntil;
    _clearExpiredVip(_lastTick);
    notifyListeners();

    var persisted = await _persistState();
    if (!persisted) {
      await _settings.waitForEntitlementOperations();
      persisted = await _persistState();
    }
    if (!persisted) {
      throw StateError('Could not persist the post-grant session balance.');
    }
  }

  /// Applies authoritative VIP changes without resetting unsaved countdown use.
  void syncAuthoritativeVip() {
    if (_isActive) {
      _applyElapsed();
    } else {
      _lastTick = _now();
    }
    _knownVipUntil = _settings.vipUntil;
    _clearExpiredVip(_lastTick);
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
    final now = _now();
    _consumeElapsed(_lastTick, now);
    _lastTick = now;
    _clearExpiredVip(now);
  }

  void _consumeElapsed(
    DateTime startedAt,
    DateTime endedAt, {
    DateTime? vipDeadline,
  }) {
    if (!endedAt.isAfter(startedAt)) return;

    var chargeFrom = startedAt;
    final vipUntil = vipDeadline ?? _knownVipUntil;
    if (vipUntil != null) {
      if (vipUntil.isAfter(endedAt) || vipUntil.isAtSameMomentAs(endedAt)) {
        return;
      }
      if (vipUntil.isAfter(chargeFrom)) chargeFrom = vipUntil;
    }

    final elapsedSeconds = endedAt.difference(chargeFrom).inSeconds;
    if (elapsedSeconds <= 0) return;
    _remaining = Duration(
      seconds: (_remaining.inSeconds - elapsedSeconds).clamp(
        0,
        _maximumRemainingSeconds,
      ),
    );
    if (_remaining == Duration.zero) {
      _isActive = false;
      _timer?.cancel();
      _timer = null;
    }
  }

  void _clearExpiredVip(DateTime now) {
    final vipUntil = _knownVipUntil;
    if (vipUntil == null || vipUntil.isAfter(now)) return;
    _knownVipUntil = null;
    unawaited(_settings.clearExpiredVip(now));
  }

  Future<bool> _persistState() async {
    final now = _now();
    final persisted = await _settings.persistRemainingAfterUsage(
      _remaining.inSeconds,
    );
    if (!persisted) return false;
    await _settings.setSessionState(active: _isActive, updatedAt: now);
    return true;
  }

  Future<void> _saveState() async {
    try {
      if (!await _persistState()) {
        await _settings.waitForEntitlementOperations();
        await _persistState();
      }
    } catch (_) {
      // A later tick/lifecycle transition retries convenience persistence.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isActive) {
        _applyElapsed();
        notifyListeners();
      }
    } else if (_isActive) {
      _applyElapsed();
      unawaited(_saveState());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}
