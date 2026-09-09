import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/entitlement_models.dart';
import 'package:globoverse/services/purchase_verification_service.dart';
import 'package:globoverse/services/session_service.dart';
import 'package:globoverse/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('active sessions count down and pause cleanly', (_) async {
    final settings = SettingsService();
    await settings.init();
    var now = DateTime.utc(2026, 9, 9, 12);
    final session = SessionService(settings, now: () => now);
    final initialSeconds = session.remaining.inSeconds;

    expect(session.start(), isTrue);
    now = now.add(const Duration(seconds: 2));
    session.pause();

    expect(session.remaining.inSeconds, initialSeconds - 2);
    expect(session.isActive, isFalse);
    session.dispose();
  });

  testWidgets('an exhausted session cannot start again', (_) async {
    final settings = SettingsService();
    await settings.init();
    await settings.persistRemainingAfterUsage(1);
    var now = DateTime.utc(2026, 9, 9, 12);
    final session = SessionService(settings, now: () => now);

    expect(session.start(), isTrue);
    now = now.add(const Duration(seconds: 2));
    session.pause();

    expect(session.remaining, Duration.zero);
    expect(session.canStart, isFalse);
    session.dispose();
  });

  testWidgets('resume charges only the interval after a stored VIP expiry', (
    _,
  ) async {
    final now = _millisecondUtcNow();
    final startedAt = now.subtract(const Duration(seconds: 90));
    final vipUntil = now.subtract(const Duration(seconds: 60));
    SharedPreferences.setMockInitialValues({
      'billing_security_version': 1,
      'remaining_seconds': 1200,
      'vip_until': vipUntil.millisecondsSinceEpoch,
      'entitlement_revision': 1,
      'entitlement_vip_until': vipUntil.millisecondsSinceEpoch,
      'session_active': true,
      'session_updated_at': startedAt.millisecondsSinceEpoch,
    });
    final settings = SettingsService();
    await settings.init();
    expect(settings.vipUntil, isNull);
    expect(settings.authoritativeVipUntil, vipUntil);
    final session = SessionService(settings, now: () => now);

    session.resume();

    expect(session.remaining.inSeconds, 1140);
    expect(session.isVip, isFalse);
    expect(session.isActive, isTrue);
    session.dispose();
  });

  testWidgets('authoritative VIP sync preserves unpersisted countdown usage', (
    _,
  ) async {
    final settings = SettingsService();
    await settings.init();
    var now = DateTime.utc(2026, 9, 9, 12);
    final session = SessionService(settings, now: () => now);
    final initialSeconds = session.remaining.inSeconds;
    expect(session.start(), isTrue);
    now = now.add(const Duration(seconds: 3));
    await settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: _millisecondUtcNow(),
        vipUntil: null,
      ),
    );

    session.syncAuthoritativeVip();

    expect(session.remaining.inSeconds, initialSeconds - 3);
    expect(session.isActive, isTrue);
    session.dispose();
  });

  testWidgets('pre-grant flush preserves active-session usage', (_) async {
    final settings = SettingsService();
    await settings.init();
    var now = DateTime.utc(2026, 9, 9, 12);
    final session = SessionService(settings, now: () => now);
    final initialSeconds = session.remaining.inSeconds;
    expect(session.start(), isTrue);
    now = now.add(const Duration(seconds: 3));

    await session.prepareForVerifiedGrant();
    now = now.add(const Duration(seconds: 2));
    session.syncAuthoritativeVip();
    expect(
      await settings.persistRemainingAfterUsage(session.remaining.inSeconds),
      isTrue,
    );
    final grant = VerifiedPurchaseGrant.sessionTime(
      verificationId: 'trusted-active-hour-1',
      productId: BillingProductIds.hourPass,
      seconds: 3600,
    );
    final wasApplied = await settings.applyVerifiedPurchaseGrant(
      grant,
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: _millisecondUtcNow(),
        vipUntil: null,
      ),
    );
    await session.syncVerifiedPurchaseEntitlements(grant, wasApplied);

    expect(wasApplied, isTrue);
    expect(settings.remainingSeconds, initialSeconds - 5 + 3600);
    expect(session.remaining.inSeconds, initialSeconds - 5 + 3600);

    await session.prepareForVerifiedGrant();
    final duplicateWasApplied = await settings.applyVerifiedPurchaseGrant(
      grant,
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: _millisecondUtcNow(),
        vipUntil: null,
      ),
    );
    await session.syncVerifiedPurchaseEntitlements(grant, duplicateWasApplied);
    expect(duplicateWasApplied, isFalse);
    expect(session.remaining.inSeconds, initialSeconds - 5 + 3600);
    session.dispose();
  });

  testWidgets('a verified hour grant updates available connection time', (
    _,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    final session = SessionService(settings);
    final initialSeconds = session.remaining.inSeconds;

    final grant = VerifiedPurchaseGrant.sessionTime(
      verificationId: 'trusted-hour-1',
      productId: BillingProductIds.hourPass,
      seconds: 3600,
    );
    final wasApplied = await settings.applyVerifiedPurchaseGrant(
      grant,
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: _millisecondUtcNow(),
        vipUntil: null,
      ),
    );
    await session.syncVerifiedPurchaseEntitlements(grant, wasApplied);

    expect(session.remaining.inSeconds, initialSeconds + 3600);
    session.dispose();
  });
}

DateTime _millisecondUtcNow() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
}
