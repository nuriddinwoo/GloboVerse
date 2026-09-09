import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'entitlement_models.dart';
import 'purchase_verification_service.dart';

class SettingsService extends ChangeNotifier {
  static const _languageKey = 'language_code';
  static const _displayNameKey = 'display_name';
  static const _onboardingKey = 'onboarding_complete';
  static const _notificationsKey = 'notifications_enabled';
  static const _remainingSecondsKey = 'remaining_seconds';
  static const _vipUntilKey = 'vip_until';
  static const _sessionActiveKey = 'session_active';
  static const _sessionUpdatedAtKey = 'session_updated_at';
  static const _legacyProcessedPurchasesKey = 'processed_purchases';
  static const _verifiedPurchaseGrantsKey = 'verified_purchase_grants';
  static const _pendingVerifiedGrantKey = 'pending_verified_grant';
  static const _entitlementRevisionKey = 'entitlement_revision';
  static const _authoritativeVipUntilKey = 'entitlement_vip_until';
  static const _pendingEntitlementSnapshotKey = 'pending_entitlement_snapshot';
  static const _billingSecurityVersionKey = 'billing_security_version';
  static const _billingSecurityVersion = 1;
  static const _defaultRemainingSeconds = 20 * 60;
  static const _maximumRemainingSeconds = 99 * 60 * 60;

  SharedPreferences? _preferences;
  String _languageCode = 'en';
  String _displayName = '';
  bool _onboardingComplete = false;
  bool _notificationsEnabled = true;
  int _remainingSeconds = _defaultRemainingSeconds;
  DateTime? _vipUntil;
  bool _sessionWasActive = false;
  DateTime? _sessionUpdatedAt;
  Set<String> _appliedVerificationIds = {};
  int _entitlementRevision = 0;
  DateTime? _authoritativeVipUntil;
  Future<void> _remainingWrite = Future<void>.value();
  Future<void> _sessionWrite = Future<void>.value();
  Future<void> _vipWrite = Future<void>.value();
  Future<void> _entitlementOperations = Future<void>.value();
  int _pendingEntitlementOperations = 0;

  String get languageCode => _languageCode;
  String get displayName => _displayName;
  bool get onboardingComplete => _onboardingComplete;
  bool get notificationsEnabled => _notificationsEnabled;
  int get remainingSeconds => _remainingSeconds;
  DateTime? get vipUntil => _vipUntil;
  DateTime? get authoritativeVipUntil => _authoritativeVipUntil;
  bool get sessionWasActive => _sessionWasActive;
  DateTime? get sessionUpdatedAt => _sessionUpdatedAt;
  int get entitlementRevision => _entitlementRevision;

  bool canAcceptSessionGrant(int seconds) {
    return seconds > 0 &&
        _remainingSeconds <= _maximumRemainingSeconds - seconds;
  }

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
        (_preferences?.getInt(_remainingSecondsKey) ?? _defaultRemainingSeconds)
            .clamp(0, _maximumRemainingSeconds);
    _sessionWasActive = _preferences?.getBool(_sessionActiveKey) ?? false;
    _appliedVerificationIds =
        (_preferences?.getStringList(_verifiedPurchaseGrantsKey) ??
                const <String>[])
            .where(_isValidVerificationId)
            .toSet();
    final storedEntitlementRevision = _preferences?.getInt(
      _entitlementRevisionKey,
    );
    _entitlementRevision =
        storedEntitlementRevision != null &&
            storedEntitlementRevision > 0 &&
            storedEntitlementRevision <= maximumEntitlementRevision
        ? storedEntitlementRevision
        : 0;
    final authoritativeVipMilliseconds = _preferences?.getInt(
      _authoritativeVipUntilKey,
    );
    _authoritativeVipUntil = _safeUtcDateTime(authoritativeVipMilliseconds);
    if (authoritativeVipMilliseconds != null &&
        _authoritativeVipUntil == null) {
      _entitlementRevision = 0;
    }
    if (_entitlementRevision == 0) _authoritativeVipUntil = null;

    final vipMilliseconds = _preferences?.getInt(_vipUntilKey);
    _vipUntil = _safeUtcDateTime(vipMilliseconds);
    if (_entitlementRevision == 0) {
      _vipUntil = null;
      _authoritativeVipUntil = null;
      await _preferences?.remove(_vipUntilKey);
      await _preferences?.remove(_authoritativeVipUntilKey);
    } else {
      final effectiveAuthoritativeVip = _effectiveVipUntil(
        _authoritativeVipUntil,
      );
      if (_vipUntil != effectiveAuthoritativeVip) {
        _vipUntil = effectiveAuthoritativeVip;
        if (_vipUntil == null) {
          await _preferences?.remove(_vipUntilKey);
        } else {
          await _preferences?.setInt(
            _vipUntilKey,
            _vipUntil!.millisecondsSinceEpoch,
          );
        }
      }
    }

    final sessionMilliseconds = _preferences?.getInt(_sessionUpdatedAtKey);
    _sessionUpdatedAt = sessionMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(sessionMilliseconds);

    await _migrateLegacyClientEntitlements();
    await _recoverPendingVerifiedGrant();
    await _recoverPendingEntitlementSnapshot();
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

  Future<void> waitForEntitlementOperations() => _entitlementOperations;

  Future<bool> persistRemainingAfterUsage(int value) async {
    final preferences = _preferences;
    if (preferences == null ||
        _pendingEntitlementOperations > 0 ||
        value < 0 ||
        value > _remainingSeconds) {
      return false;
    }
    final safeValue = value;
    _remainingSeconds = safeValue;
    final write = _remainingWrite.then((_) async {
      if (!await preferences.setInt(_remainingSecondsKey, safeValue)) {
        throw StateError('Could not persist consumed session time.');
      }
    });
    _remainingWrite = write.catchError((Object _) {});
    await write;
    return true;
  }

  Future<void> clearExpiredVip(DateTime now) async {
    if (_preferences == null || _pendingEntitlementOperations > 0) return;
    final currentVipUntil = _vipUntil;
    if (currentVipUntil == null || currentVipUntil.isAfter(now.toUtc())) return;
    _vipUntil = null;
    notifyListeners();
    final write = _vipWrite.then((_) async {
      await _preferences?.remove(_vipUntilKey);
    });
    _vipWrite = write.catchError((Object _) {});
    await write;
  }

  bool hasAppliedVerifiedGrant(String verificationId) {
    return _appliedVerificationIds.contains(verificationId);
  }

  Future<bool> applyVerifiedPurchaseGrant(
    VerifiedPurchaseGrant grant,
    AuthoritativeEntitlementSnapshot snapshot,
  ) async {
    final preferences = _preferences;
    if (preferences == null) {
      throw StateError('Settings must be initialized before applying a grant.');
    }
    _validateVerifiedGrant(grant);
    _validateEntitlementSnapshot(snapshot);
    if (grant.kind == VerifiedEntitlementKind.vip &&
        grant.vipUntil != snapshot.vipUntil) {
      throw const FormatException(
        'Verified VIP grant does not match its entitlement snapshot.',
      );
    }
    return _runEntitlementOperation(() async {
      await _recoverPendingVerifiedGrant();
      await _recoverPendingEntitlementSnapshot();
      if (_appliedVerificationIds.contains(grant.verificationId)) {
        final outcome = await _applyEntitlementSnapshot(snapshot);
        if (outcome == EntitlementReconciliationOutcome.applied) {
          notifyListeners();
        }
        return false;
      }

      await Future.wait([_remainingWrite, _vipWrite]);
      var targetRemainingSeconds = _remainingSeconds;
      final snapshotState = _targetSnapshotState(snapshot);
      final targetVipUntil = snapshotState.vipUntil;
      final targetEntitlementRevision = snapshotState.revision;
      if (grant.kind == VerifiedEntitlementKind.sessionTime) {
        final seconds = grant.sessionSeconds!;
        if (!canAcceptSessionGrant(seconds)) {
          final outcome = await _applyEntitlementSnapshot(snapshot);
          if (outcome == EntitlementReconciliationOutcome.applied) {
            notifyListeners();
          }
          throw StateError(
            'Verified connection time exceeds local storage capacity.',
          );
        }
        targetRemainingSeconds = _remainingSeconds + seconds;
      }

      final journal = jsonEncode({
        'verificationId': grant.verificationId,
        'remainingSeconds': targetRemainingSeconds,
        'vipUntil': targetVipUntil?.millisecondsSinceEpoch,
        'authoritativeVipUntil':
            snapshotState.authoritativeVipUntil?.millisecondsSinceEpoch,
        'entitlementRevision': targetEntitlementRevision,
      });
      if (!await preferences.setString(_pendingVerifiedGrantKey, journal)) {
        throw StateError('Could not persist the verified grant journal.');
      }

      await _recoverPendingVerifiedGrant();
      notifyListeners();
      return true;
    });
  }

  Future<EntitlementReconciliationOutcome> reconcileEntitlements(
    AuthoritativeEntitlementSnapshot snapshot,
  ) async {
    if (_preferences == null) {
      throw StateError(
        'Settings must be initialized before reconciling entitlements.',
      );
    }
    _validateEntitlementSnapshot(snapshot);
    return _runEntitlementOperation(() async {
      await _recoverPendingVerifiedGrant();
      await _recoverPendingEntitlementSnapshot();
      await Future.wait([_remainingWrite, _vipWrite]);
      final outcome = await _applyEntitlementSnapshot(snapshot);
      if (outcome == EntitlementReconciliationOutcome.applied) {
        notifyListeners();
      }
      return outcome;
    });
  }

  Future<T> _runEntitlementOperation<T>(Future<T> Function() operation) {
    _pendingEntitlementOperations += 1;
    final result = _entitlementOperations.then((_) => operation());
    _entitlementOperations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result.whenComplete(() {
      _pendingEntitlementOperations -= 1;
    });
  }

  void _validateEntitlementSnapshot(AuthoritativeEntitlementSnapshot snapshot) {
    final generatedAt = snapshot.generatedAt;
    final vipUntil = snapshot.vipUntil;
    final now = DateTime.now().toUtc();
    if (snapshot.revision <= 0 ||
        snapshot.revision > maximumEntitlementRevision ||
        !generatedAt.isUtc ||
        generatedAt.microsecond != 0 ||
        generatedAt.year < 2000 ||
        generatedAt.year > 2200 ||
        generatedAt.isBefore(now.subtract(const Duration(hours: 1))) ||
        generatedAt.isAfter(now.add(const Duration(minutes: 5))) ||
        (vipUntil != null &&
            (!vipUntil.isUtc ||
                vipUntil.microsecond != 0 ||
                !vipUntil.isAfter(now) ||
                !vipUntil.isAfter(generatedAt) ||
                vipUntil.isAfter(
                  generatedAt.add(maximumVerifiedVipHorizon),
                )))) {
      throw const FormatException('Entitlement snapshot is invalid.');
    }
  }

  _EntitlementTarget _targetSnapshotState(
    AuthoritativeEntitlementSnapshot snapshot,
  ) {
    final effectiveVipUntil = _effectiveVipUntil(snapshot.vipUntil);
    if (snapshot.revision < _entitlementRevision) {
      return _EntitlementTarget(
        _entitlementRevision,
        _effectiveVipUntil(_vipUntil),
        _authoritativeVipUntil,
      );
    }
    if (snapshot.revision == _entitlementRevision) {
      if (_authoritativeVipUntil != snapshot.vipUntil) {
        throw const FormatException(
          'Entitlement snapshot conflicts with its stored revision.',
        );
      }
      return _EntitlementTarget(
        _entitlementRevision,
        effectiveVipUntil,
        snapshot.vipUntil,
      );
    }
    return _EntitlementTarget(
      snapshot.revision,
      effectiveVipUntil,
      snapshot.vipUntil,
    );
  }

  DateTime? _effectiveVipUntil(DateTime? value) {
    if (value == null || !value.isAfter(DateTime.now().toUtc())) return null;
    return value;
  }

  Future<EntitlementReconciliationOutcome> _applyEntitlementSnapshot(
    AuthoritativeEntitlementSnapshot snapshot,
  ) async {
    if (snapshot.revision < _entitlementRevision) {
      return EntitlementReconciliationOutcome.stale;
    }
    final target = _targetSnapshotState(snapshot);
    if (snapshot.revision == _entitlementRevision &&
        _effectiveVipUntil(_vipUntil) == target.vipUntil) {
      return EntitlementReconciliationOutcome.unchanged;
    }

    final preferences = _preferences!;
    final journal = jsonEncode({
      'revision': target.revision,
      'vipUntil': target.vipUntil?.millisecondsSinceEpoch,
      'authoritativeVipUntil':
          target.authoritativeVipUntil?.millisecondsSinceEpoch,
    });
    if (!await preferences.setString(_pendingEntitlementSnapshotKey, journal)) {
      throw StateError('Could not persist the entitlement snapshot journal.');
    }
    await _recoverPendingEntitlementSnapshot();
    return EntitlementReconciliationOutcome.applied;
  }

  void _validateVerifiedGrant(VerifiedPurchaseGrant grant) {
    if (!_isValidVerificationId(grant.verificationId)) {
      throw const FormatException('Verified grant ID is invalid.');
    }
    final isHourPass =
        grant.productId == BillingProductIds.hourPass &&
        grant.kind == VerifiedEntitlementKind.sessionTime &&
        grant.sessionSeconds == 3600 &&
        grant.vipUntil == null;
    final now = DateTime.now().toUtc();
    final isMonthlyVip =
        grant.productId == BillingProductIds.monthlyVip &&
        grant.kind == VerifiedEntitlementKind.vip &&
        grant.sessionSeconds == null &&
        grant.vipUntil != null &&
        grant.vipUntil!.isUtc &&
        grant.vipUntil!.microsecond == 0 &&
        grant.vipUntil!.isAfter(now) &&
        !grant.vipUntil!.isAfter(now.add(maximumVerifiedVipHorizon));
    if (!isHourPass && !isMonthlyVip) {
      throw const FormatException('Verified grant does not match its product.');
    }
  }

  Future<void> _migrateLegacyClientEntitlements() async {
    final preferences = _preferences!;
    final version = preferences.getInt(_billingSecurityVersionKey) ?? 0;
    if (version >= _billingSecurityVersion) return;

    _remainingSeconds = _remainingSeconds.clamp(0, _defaultRemainingSeconds);
    _vipUntil = null;
    _entitlementRevision = 0;
    _authoritativeVipUntil = null;
    if (!await preferences.setInt(_remainingSecondsKey, _remainingSeconds)) {
      throw StateError('Could not migrate connection time securely.');
    }
    await preferences.remove(_vipUntilKey);
    await preferences.remove(_entitlementRevisionKey);
    await preferences.remove(_authoritativeVipUntilKey);
    await preferences.remove(_pendingEntitlementSnapshotKey);
    await preferences.remove(_legacyProcessedPurchasesKey);
    if (!await preferences.setInt(
      _billingSecurityVersionKey,
      _billingSecurityVersion,
    )) {
      throw StateError('Could not finish the billing security migration.');
    }
  }

  Future<void> _recoverPendingVerifiedGrant() async {
    final preferences = _preferences;
    if (preferences == null) return;
    final encoded = preferences.getString(_pendingVerifiedGrantKey);
    if (encoded == null) return;

    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } catch (_) {
      await preferences.remove(_pendingVerifiedGrantKey);
      return;
    }
    if (decoded is! Map) {
      await preferences.remove(_pendingVerifiedGrantKey);
      return;
    }

    final verificationId = decoded['verificationId'];
    final remainingSeconds = decoded['remainingSeconds'];
    final vipMilliseconds = decoded['vipUntil'];
    final authoritativeVipMilliseconds = decoded['authoritativeVipUntil'];
    final entitlementRevision = decoded['entitlementRevision'];
    if (verificationId is! String ||
        !_isValidVerificationId(verificationId) ||
        remainingSeconds is! int ||
        remainingSeconds < 0 ||
        remainingSeconds > _maximumRemainingSeconds ||
        entitlementRevision is! int ||
        entitlementRevision <= 0 ||
        entitlementRevision > maximumEntitlementRevision ||
        entitlementRevision < _entitlementRevision ||
        (vipMilliseconds != null && vipMilliseconds is! int) ||
        (authoritativeVipMilliseconds != null &&
            authoritativeVipMilliseconds is! int)) {
      await preferences.remove(_pendingVerifiedGrantKey);
      return;
    }
    final targetVipUntil = vipMilliseconds is int
        ? _safeUtcDateTime(vipMilliseconds)
        : null;
    final targetAuthoritativeVipUntil = authoritativeVipMilliseconds is int
        ? _safeUtcDateTime(authoritativeVipMilliseconds)
        : null;
    if ((vipMilliseconds != null && targetVipUntil == null) ||
        (authoritativeVipMilliseconds != null &&
            targetAuthoritativeVipUntil == null)) {
      await preferences.remove(_pendingVerifiedGrantKey);
      return;
    }
    if (_appliedVerificationIds.contains(verificationId)) {
      await preferences.remove(_pendingVerifiedGrantKey);
      return;
    }

    if (!await preferences.setInt(_remainingSecondsKey, remainingSeconds)) {
      throw StateError('Could not persist verified connection time.');
    }
    if (vipMilliseconds == null) {
      if (!await preferences.remove(_vipUntilKey)) {
        throw StateError('Could not persist verified VIP revocation.');
      }
    } else if (!await preferences.setInt(_vipUntilKey, vipMilliseconds)) {
      throw StateError('Could not persist verified VIP access.');
    }
    if (authoritativeVipMilliseconds == null) {
      if (!await preferences.remove(_authoritativeVipUntilKey)) {
        throw StateError('Could not persist authoritative VIP state.');
      }
    } else if (!await preferences.setInt(
      _authoritativeVipUntilKey,
      authoritativeVipMilliseconds,
    )) {
      throw StateError('Could not persist authoritative VIP state.');
    }
    if (!await preferences.setInt(
      _entitlementRevisionKey,
      entitlementRevision,
    )) {
      throw StateError('Could not persist the entitlement revision.');
    }

    final appliedIds = {..._appliedVerificationIds, verificationId};
    if (!await preferences.setStringList(
      _verifiedPurchaseGrantsKey,
      appliedIds.toList(growable: false),
    )) {
      throw StateError('Could not persist verified grant history.');
    }

    _remainingSeconds = remainingSeconds;
    _vipUntil = targetVipUntil;
    _authoritativeVipUntil = targetAuthoritativeVipUntil;
    _entitlementRevision = entitlementRevision;
    _appliedVerificationIds = appliedIds;
    await preferences.remove(_pendingVerifiedGrantKey);
  }

  Future<void> _recoverPendingEntitlementSnapshot() async {
    final preferences = _preferences;
    if (preferences == null) return;
    final encoded = preferences.getString(_pendingEntitlementSnapshotKey);
    if (encoded == null) return;

    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } catch (_) {
      await preferences.remove(_pendingEntitlementSnapshotKey);
      return;
    }
    if (decoded is! Map ||
        decoded.length != 3 ||
        !decoded.containsKey('revision') ||
        !decoded.containsKey('vipUntil') ||
        !decoded.containsKey('authoritativeVipUntil')) {
      await preferences.remove(_pendingEntitlementSnapshotKey);
      return;
    }

    final revision = decoded['revision'];
    final vipMilliseconds = decoded['vipUntil'];
    final authoritativeVipMilliseconds = decoded['authoritativeVipUntil'];
    if (revision is! int ||
        revision <= 0 ||
        revision > maximumEntitlementRevision ||
        (vipMilliseconds != null && vipMilliseconds is! int) ||
        (authoritativeVipMilliseconds != null &&
            authoritativeVipMilliseconds is! int)) {
      await preferences.remove(_pendingEntitlementSnapshotKey);
      return;
    }
    final targetVipUntil = vipMilliseconds is int
        ? _safeUtcDateTime(vipMilliseconds)
        : null;
    final targetAuthoritativeVipUntil = authoritativeVipMilliseconds is int
        ? _safeUtcDateTime(authoritativeVipMilliseconds)
        : null;
    if ((vipMilliseconds != null && targetVipUntil == null) ||
        (authoritativeVipMilliseconds != null &&
            targetAuthoritativeVipUntil == null)) {
      await preferences.remove(_pendingEntitlementSnapshotKey);
      return;
    }
    if (revision < _entitlementRevision) {
      await preferences.remove(_pendingEntitlementSnapshotKey);
      return;
    }

    if (vipMilliseconds == null) {
      if (!await preferences.remove(_vipUntilKey)) {
        throw StateError('Could not persist authoritative VIP revocation.');
      }
    } else if (!await preferences.setInt(_vipUntilKey, vipMilliseconds)) {
      throw StateError('Could not persist authoritative VIP access.');
    }
    if (authoritativeVipMilliseconds == null) {
      if (!await preferences.remove(_authoritativeVipUntilKey)) {
        throw StateError('Could not persist authoritative VIP state.');
      }
    } else if (!await preferences.setInt(
      _authoritativeVipUntilKey,
      authoritativeVipMilliseconds,
    )) {
      throw StateError('Could not persist authoritative VIP state.');
    }
    if (!await preferences.setInt(_entitlementRevisionKey, revision)) {
      throw StateError('Could not persist the entitlement revision.');
    }

    _vipUntil = targetVipUntil;
    _authoritativeVipUntil = targetAuthoritativeVipUntil;
    _entitlementRevision = revision;
    if (!await preferences.remove(_pendingEntitlementSnapshotKey)) {
      throw StateError('Could not finish entitlement reconciliation.');
    }
  }

  static bool _isValidVerificationId(String value) {
    return value.length <= 200 &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value);
  }

  static DateTime? _safeUtcDateTime(int? milliseconds) {
    if (milliseconds == null) return null;
    try {
      final value = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
      return value.year >= 2000 && value.year <= 2200 ? value : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSessionState({
    required bool active,
    required DateTime updatedAt,
  }) async {
    final preferences = _preferences;
    if (preferences == null) {
      throw StateError('Settings must be initialized before saving a session.');
    }
    final write = _sessionWrite.then((_) async {
      final persisted = await Future.wait([
        preferences.setBool(_sessionActiveKey, active),
        preferences.setInt(
          _sessionUpdatedAtKey,
          updatedAt.millisecondsSinceEpoch,
        ),
      ]);
      if (persisted.any((value) => !value)) {
        throw StateError('Could not persist the session state.');
      }
      _sessionWasActive = active;
      _sessionUpdatedAt = updatedAt;
    });
    _sessionWrite = write.catchError((Object _) {});
    await write;
  }
}

class _EntitlementTarget {
  const _EntitlementTarget(
    this.revision,
    this.vipUntil,
    this.authoritativeVipUntil,
  );

  final int revision;
  final DateTime? vipUntil;
  final DateTime? authoritativeVipUntil;
}
