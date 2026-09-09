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

  testWidgets('a verified hour grant updates available connection time', (
    _,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    final session = SessionService(settings);
    final initialSeconds = session.remaining.inSeconds;

    await settings.applyVerifiedPurchaseGrant(
      VerifiedPurchaseGrant.sessionTime(
        verificationId: 'trusted-hour-1',
        productId: BillingProductIds.hourPass,
        seconds: 3600,
      ),
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: _millisecondUtcNow(),
        vipUntil: null,
      ),
    );
    session.syncVerifiedEntitlements();

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
