import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/entitlement_models.dart';
import 'package:globoverse/services/purchase_verification_service.dart';
import 'package:globoverse/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('session persistence cannot manufacture additional time', () async {
    final settings = SettingsService();
    await settings.init();
    final initialSeconds = settings.remainingSeconds;

    final saved = await settings.persistRemainingAfterUsage(initialSeconds + 1);

    expect(saved, isFalse);
    expect(settings.remainingSeconds, initialSeconds);
  });

  test('a newer authoritative snapshot revokes local VIP access', () async {
    final settings = SettingsService();
    await settings.init();
    final generatedAt = _millisecondUtcNow();
    final vipUntil = generatedAt.add(const Duration(days: 30));

    await settings.applyVerifiedPurchaseGrant(
      VerifiedPurchaseGrant.vip(
        verificationId: 'apple:vip-1',
        productId: BillingProductIds.monthlyVip,
        vipUntil: vipUntil,
      ),
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: generatedAt,
        vipUntil: vipUntil,
      ),
    );
    final outcome = await settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 2,
        generatedAt: generatedAt.add(const Duration(minutes: 1)),
        vipUntil: null,
      ),
    );

    expect(outcome, EntitlementReconciliationOutcome.applied);
    expect(settings.entitlementRevision, 2);
    expect(settings.vipUntil, isNull);
  });

  test('a stale snapshot cannot restore revoked VIP access', () async {
    final settings = SettingsService();
    await settings.init();
    final generatedAt = _millisecondUtcNow();
    await settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 2,
        generatedAt: generatedAt,
        vipUntil: null,
      ),
    );

    final outcome = await settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: generatedAt,
        vipUntil: generatedAt.add(const Duration(days: 30)),
      ),
    );

    expect(outcome, EntitlementReconciliationOutcome.stale);
    expect(settings.entitlementRevision, 2);
    expect(settings.vipUntil, isNull);
  });

  test('the same revision repairs missing local VIP state', () async {
    final settings = SettingsService();
    await settings.init();
    final generatedAt = _millisecondUtcNow();
    final vipUntil = generatedAt.add(const Duration(days: 30));
    final snapshot = AuthoritativeEntitlementSnapshot(
      revision: 3,
      generatedAt: generatedAt,
      vipUntil: vipUntil,
    );
    await settings.reconcileEntitlements(snapshot);
    await settings.clearExpiredVip(vipUntil.add(const Duration(seconds: 1)));

    final outcome = await settings.reconcileEntitlements(snapshot);

    expect(outcome, EntitlementReconciliationOutcome.applied);
    expect(settings.entitlementRevision, 3);
    expect(settings.vipUntil, vipUntil);

    final reloaded = SettingsService();
    await reloaded.init();
    expect(reloaded.entitlementRevision, 3);
    expect(reloaded.vipUntil, vipUntil);
  });

  test('the same revision cannot carry conflicting VIP state', () async {
    final settings = SettingsService();
    await settings.init();
    final generatedAt = _millisecondUtcNow();
    await settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 4,
        generatedAt: generatedAt,
        vipUntil: null,
      ),
    );

    await expectLater(
      settings.reconcileEntitlements(
        AuthoritativeEntitlementSnapshot(
          revision: 4,
          generatedAt: generatedAt,
          vipUntil: generatedAt.add(const Duration(days: 30)),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(settings.vipUntil, isNull);
  });

  test('startup recovers an interrupted authoritative revocation', () async {
    final oldVip = _millisecondUtcNow().add(const Duration(days: 20));
    SharedPreferences.setMockInitialValues({
      'billing_security_version': 1,
      'vip_until': oldVip.millisecondsSinceEpoch,
      'entitlement_revision': 1,
      'entitlement_vip_until': oldVip.millisecondsSinceEpoch,
      'pending_entitlement_snapshot': jsonEncode({
        'revision': 2,
        'vipUntil': null,
        'authoritativeVipUntil': null,
      }),
    });

    final settings = SettingsService();
    await settings.init();

    expect(settings.entitlementRevision, 2);
    expect(settings.vipUntil, isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('pending_entitlement_snapshot'), isFalse);
  });

  test(
    'a verified hour is not partially discarded at the local limit',
    () async {
      const maximumSeconds = 99 * 60 * 60;
      SharedPreferences.setMockInitialValues({
        'billing_security_version': 1,
        'remaining_seconds': maximumSeconds,
      });
      final settings = SettingsService();
      await settings.init();
      final generatedAt = _millisecondUtcNow();

      await expectLater(
        settings.applyVerifiedPurchaseGrant(
          VerifiedPurchaseGrant.sessionTime(
            verificationId: 'google:capacity-hour',
            productId: BillingProductIds.hourPass,
            seconds: 3600,
          ),
          AuthoritativeEntitlementSnapshot(
            revision: 5,
            generatedAt: generatedAt,
            vipUntil: null,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(settings.remainingSeconds, maximumSeconds);
      expect(settings.entitlementRevision, 5);
      expect(settings.hasAppliedVerifiedGrant('google:capacity-hour'), isFalse);
    },
  );

  test(
    'session writes cannot overwrite a queued entitlement snapshot',
    () async {
      final settings = SettingsService();
      await settings.init();
      final initialSeconds = settings.remainingSeconds;
      final reconciliation = settings.reconcileEntitlements(
        AuthoritativeEntitlementSnapshot(
          revision: 6,
          generatedAt: _millisecondUtcNow(),
          vipUntil: null,
        ),
      );

      final saved = await settings.persistRemainingAfterUsage(1);
      await reconciliation;

      expect(saved, isFalse);
      expect(settings.remainingSeconds, initialSeconds);
      expect(settings.entitlementRevision, 6);
    },
  );

  test('queued reconciliation never lets an older revision win', () async {
    final settings = SettingsService();
    await settings.init();
    final generatedAt = _millisecondUtcNow();

    final newest = settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 10,
        generatedAt: generatedAt,
        vipUntil: null,
      ),
    );
    final older = settings.reconcileEntitlements(
      AuthoritativeEntitlementSnapshot(
        revision: 9,
        generatedAt: generatedAt,
        vipUntil: generatedAt.add(const Duration(days: 30)),
      ),
    );

    expect(await newest, EntitlementReconciliationOutcome.applied);
    expect(await older, EntitlementReconciliationOutcome.stale);
    expect(settings.entitlementRevision, 10);
    expect(settings.vipUntil, isNull);
  });
}

DateTime _millisecondUtcNow() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
}
