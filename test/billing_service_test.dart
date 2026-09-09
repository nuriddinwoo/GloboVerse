import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/l10n/l10n_state.dart';
import 'package:globoverse/screens/profile/billing_sheet.dart';
import 'package:globoverse/services/billing_service.dart';
import 'package:globoverse/services/billing_store.dart';
import 'package:globoverse/services/entitlement_models.dart';
import 'package:globoverse/services/entitlement_reconciliation_service.dart';
import 'package:globoverse/services/purchase_verification_service.dart';
import 'package:globoverse/services/settings_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('legacy client-trusted entitlements are invalidated once', () async {
    SharedPreferences.setMockInitialValues({
      'remaining_seconds': 7200,
      'vip_until': DateTime.utc(2026, 12, 1).millisecondsSinceEpoch,
      'processed_purchases': ['unverified-client-purchase'],
    });
    final settings = SettingsService();

    await settings.init();

    expect(settings.remainingSeconds, const Duration(minutes: 20).inSeconds);
    expect(settings.vipUntil, isNull);
  });

  test(
    'recovers an interrupted verified grant without double delivery',
    () async {
      SharedPreferences.setMockInitialValues({
        'billing_security_version': 1,
        'remaining_seconds': 1200,
        'pending_verified_grant': jsonEncode({
          'verificationId': 'server:recovered-hour',
          'remainingSeconds': 4800,
          'vipUntil': null,
          'authoritativeVipUntil': null,
          'entitlementRevision': 1,
        }),
      });
      final settings = SettingsService();
      await settings.init();

      expect(settings.remainingSeconds, 4800);
      expect(settings.hasAppliedVerifiedGrant('server:recovered-hour'), isTrue);

      final reloaded = SettingsService();
      await reloaded.init();
      expect(reloaded.remainingSeconds, 4800);
      expect(reloaded.hasAppliedVerifiedGrant('server:recovered-hour'), isTrue);
    },
  );

  test(
    'missing backend verification disables delivery and store finish',
    () async {
      final settings = SettingsService();
      await settings.init();
      final initialSeconds = settings.remainingSeconds;
      final store = _FakeBillingStore();
      final verifier = _FakePurchaseVerifier(configured: false);
      final billing = BillingService(
        settings,
        store: store,
        verifier: verifier,
      );
      addTearDown(() async {
        billing.dispose();
        await store.close();
      });

      await billing.init();
      expect(billing.status, BillingStatus.verificationRequired);
      expect(billing.canPurchase, isFalse);

      final handled = _nextStatus(billing, BillingStatus.verificationRequired);
      store.emit([_purchase()]);
      await handled;

      expect(verifier.proofs, isEmpty);
      expect(store.finishedPurchases, isEmpty);
      expect(settings.remainingSeconds, initialSeconds);
      expect(settings.vipUntil, isNull);
    },
  );

  testWidgets('billing UI explains and enforces fail-closed verification', (
    tester,
  ) async {
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore();
    final billing = BillingService(
      settings,
      store: store,
      verifier: _FakePurchaseVerifier(configured: false),
    );
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });
    await billing.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: L10nState('en')),
          ChangeNotifierProvider.value(value: billing),
        ],
        child: const MaterialApp(home: Scaffold(body: BillingSheet())),
      ),
    );

    expect(
      find.text(
        'Secure purchase verification is not configured. '
        'No time or VIP access can be added.',
      ),
      findsOneWidget,
    );
    final hourCard = find.ancestor(
      of: find.text('One-hour pass'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(hourCard).onTap, isNull);
    final restore = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Restore purchases'),
    );
    expect(restore.onPressed, isNull);
  });

  testWidgets('missing store products never show fabricated prices', (
    tester,
  ) async {
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore();
    final billing = BillingService(
      settings,
      store: store,
      verifier: _FakePurchaseVerifier(),
    );
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });
    await billing.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: L10nState('en')),
          ChangeNotifierProvider.value(value: billing),
        ],
        child: const MaterialApp(home: Scaffold(body: BillingSheet())),
      ),
    );

    expect(billing.status, BillingStatus.productsUnavailable);
    expect(
      find.text('Store products are not available right now.'),
      findsOneWidget,
    );
    expect(find.text('—'), findsNWidgets(2));
    final hourCard = find.ancestor(
      of: find.text('One-hour pass'),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(hourCard).onTap, isNull);
  });

  testWidgets('billing UI explains the local hour-pass capacity limit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'billing_security_version': 1,
      'remaining_seconds': 99 * 60 * 60,
    });
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore();
    final billing = BillingService(
      settings,
      store: store,
      verifier: _FakePurchaseVerifier(),
    );
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });
    await billing.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: L10nState('en')),
          ChangeNotifierProvider.value(value: billing),
        ],
        child: const MaterialApp(home: Scaffold(body: BillingSheet())),
      ),
    );

    expect(
      find.text(
        'Use some saved connection time before buying another one-hour pass.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('billing UI exposes a retryable entitlement refresh error', (
    tester,
  ) async {
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore();
    final billing = BillingService(
      settings,
      store: store,
      verifier: _FakePurchaseVerifier(),
    );
    final reconciliation = EntitlementReconciliationService(
      settings,
      source: _ThrowingSnapshotSource(),
    );
    addTearDown(() async {
      reconciliation.dispose();
      billing.dispose();
      await store.close();
    });
    await billing.init();
    await reconciliation.refresh();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: L10nState('en')),
          ChangeNotifierProvider.value(value: billing),
          ChangeNotifierProvider.value(value: reconciliation),
        ],
        child: const MaterialApp(home: Scaffold(body: BillingSheet())),
      ),
    );

    expect(
      find.text(
        'Current VIP status could not be refreshed. No new access was added; '
        'the app will retry.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry access check'), findsOneWidget);
  });

  test('a verified grant is journaled and delivered only once', () async {
    final settings = SettingsService();
    await settings.init();
    final initialSeconds = settings.remainingSeconds;
    final store = _FakeBillingStore(expectedFinishes: 1);
    final verifier = _FakePurchaseVerifier(
      result: PurchaseVerificationResult.verified(
        VerifiedPurchaseGrant.sessionTime(
          verificationId: 'google:trusted-order-1',
          productId: BillingProductIds.hourPass,
          seconds: 3600,
        ),
        _snapshot(),
      ),
    );
    final billing = BillingService(settings, store: store, verifier: verifier);
    var entitlementNotifications = 0;
    billing.onEntitlementsChanged = () => entitlementNotifications += 1;
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });

    await billing.init();
    var successfulUpdates = 0;
    final processedTwice = Completer<void>();
    billing.addListener(() {
      if (billing.status == BillingStatus.success) {
        successfulUpdates += 1;
        if (successfulUpdates == 2 && !processedTwice.isCompleted) {
          processedTwice.complete();
        }
      }
    });
    final purchase = _purchase();
    store.emit([purchase]);
    store.emit([purchase]);
    await processedTwice.future.timeout(const Duration(seconds: 2));

    expect(billing.status, BillingStatus.success);
    expect(verifier.proofs, hasLength(2));
    expect(
      verifier.proofs.every(
        (proof) =>
            proof.serverVerificationData == 'server-receipt-token' &&
            proof.productId == BillingProductIds.hourPass,
      ),
      isTrue,
    );
    expect(settings.remainingSeconds, initialSeconds + 3600);
    expect(settings.hasAppliedVerifiedGrant('google:trusted-order-1'), isTrue);
    expect(store.finishedPurchases, hasLength(1));
    expect(store.finishedConsumableFlags, [isTrue]);
    expect(entitlementNotifications, 2);
  });

  test(
    'a verified transaction stays idempotent after settings reload',
    () async {
      final snapshot = _snapshot();
      final grant = VerifiedPurchaseGrant.sessionTime(
        verificationId: 'google:restart-order-1',
        productId: BillingProductIds.hourPass,
        seconds: 3600,
      );
      final initialSettings = SettingsService();
      await initialSettings.init();
      await initialSettings.applyVerifiedPurchaseGrant(grant, snapshot);
      final grantedSeconds = initialSettings.remainingSeconds;

      final reloadedSettings = SettingsService();
      await reloadedSettings.init();
      final store = _FakeBillingStore(expectedFinishes: 1);
      final billing = BillingService(
        reloadedSettings,
        store: store,
        verifier: _FakePurchaseVerifier(
          result: PurchaseVerificationResult.verified(grant, snapshot),
        ),
      );
      addTearDown(() async {
        billing.dispose();
        await store.close();
      });

      await billing.init();
      store.emit([_purchase()]);
      await store.expectedFinishes;

      expect(reloadedSettings.remainingSeconds, grantedSeconds);
      expect(store.finishedConsumableFlags, [isTrue]);
    },
  );

  test(
    'a definitive backend rejection grants nothing but finishes the item',
    () async {
      final settings = SettingsService();
      await settings.init();
      final initialSeconds = settings.remainingSeconds;
      final store = _FakeBillingStore(expectedFinishes: 1);
      final verifier = _FakePurchaseVerifier(
        result: const PurchaseVerificationResult.rejected(),
      );
      final billing = BillingService(
        settings,
        store: store,
        verifier: verifier,
      );
      addTearDown(() async {
        billing.dispose();
        await store.close();
      });

      await billing.init();
      store.emit([_purchase()]);
      await store.expectedFinishes;

      expect(billing.status, BillingStatus.verificationFailed);
      expect(settings.remainingSeconds, initialSeconds);
      expect(settings.vipUntil, isNull);
      expect(store.finishedPurchases, hasLength(1));
      expect(store.finishedConsumableFlags, [isTrue]);
    },
  );

  test('a canceled hour-pass event is completed without consumption', () async {
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore(expectedFinishes: 1);
    final verifier = _FakePurchaseVerifier();
    final billing = BillingService(settings, store: store, verifier: verifier);
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });

    await billing.init();
    store.emit([_purchase(status: PurchaseStatus.canceled)]);
    await store.expectedFinishes;

    expect(verifier.proofs, isEmpty);
    expect(store.finishedPurchases, hasLength(1));
    expect(store.finishedConsumableFlags, [isFalse]);
  });

  test('a store error event is completed without consumption', () async {
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore(expectedFinishes: 1);
    final verifier = _FakePurchaseVerifier();
    final billing = BillingService(settings, store: store, verifier: verifier);
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });

    await billing.init();
    store.emit([_purchase(status: PurchaseStatus.error)]);
    await store.expectedFinishes;

    expect(billing.status, BillingStatus.error);
    expect(billing.error, 'Store transaction failed.');
    expect(verifier.proofs, isEmpty);
    expect(store.finishedConsumableFlags, [isFalse]);
  });

  test('restore also requests an authoritative account snapshot', () async {
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore();
    final billing = BillingService(
      settings,
      store: store,
      verifier: _FakePurchaseVerifier(),
    );
    var reconciliationRequests = 0;
    billing.onReconciliationRequested = () async {
      reconciliationRequests += 1;
    };
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });

    await billing.init();
    await billing.restorePurchases();

    expect(reconciliationRequests, 1);
  });

  test('a restored subscription is verified before VIP is restored', () async {
    final settings = SettingsService();
    await settings.init();
    final generatedAt = _millisecondUtcNow();
    final vipUntil = generatedAt.add(const Duration(days: 30));
    final store = _FakeBillingStore(expectedFinishes: 1);
    final verifier = _FakePurchaseVerifier(
      result: PurchaseVerificationResult.verified(
        VerifiedPurchaseGrant.vip(
          verificationId: 'apple:restored-vip-1',
          productId: BillingProductIds.monthlyVip,
          vipUntil: vipUntil,
        ),
        AuthoritativeEntitlementSnapshot(
          revision: 3,
          generatedAt: generatedAt,
          vipUntil: vipUntil,
        ),
      ),
    );
    final billing = BillingService(settings, store: store, verifier: verifier);
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });

    await billing.init();
    store.emit([
      _purchase(
        status: PurchaseStatus.restored,
        productId: BillingProductIds.monthlyVip,
      ),
    ]);
    await store.expectedFinishes;

    expect(verifier.proofs.single.isRestore, isTrue);
    expect(settings.vipUntil, vipUntil);
    expect(settings.entitlementRevision, 3);
    expect(store.finishedConsumableFlags, [isFalse]);
  });

  test('a verified hour at capacity remains unfinished for retry', () async {
    const maximumSeconds = 99 * 60 * 60;
    SharedPreferences.setMockInitialValues({
      'billing_security_version': 1,
      'remaining_seconds': maximumSeconds,
    });
    final settings = SettingsService();
    await settings.init();
    final store = _FakeBillingStore();
    final verifier = _FakePurchaseVerifier(
      result: PurchaseVerificationResult.verified(
        VerifiedPurchaseGrant.sessionTime(
          verificationId: 'google:capacity-retry',
          productId: BillingProductIds.hourPass,
          seconds: 3600,
        ),
        _snapshot(revision: 11),
      ),
    );
    final billing = BillingService(settings, store: store, verifier: verifier);
    addTearDown(() async {
      billing.dispose();
      await store.close();
    });

    await billing.init();
    final handled = _nextStatus(billing, BillingStatus.verificationError);
    store.emit([_purchase()]);
    await handled;

    expect(settings.remainingSeconds, maximumSeconds);
    expect(settings.hasAppliedVerifiedGrant('google:capacity-retry'), isFalse);
    expect(settings.entitlementRevision, 11);
    expect(store.finishedPurchases, isEmpty);
  });

  test(
    'a backend-pending purchase grants nothing and stays unfinished',
    () async {
      final settings = SettingsService();
      await settings.init();
      final initialSeconds = settings.remainingSeconds;
      final store = _FakeBillingStore();
      final verifier = _FakePurchaseVerifier(
        result: const PurchaseVerificationResult.pending(),
      );
      final billing = BillingService(
        settings,
        store: store,
        verifier: verifier,
      );
      addTearDown(() async {
        billing.dispose();
        await store.close();
      });

      await billing.init();
      final handled = _nextStatus(billing, BillingStatus.verificationPending);
      store.emit([_purchase()]);
      await handled;

      expect(settings.remainingSeconds, initialSeconds);
      expect(settings.vipUntil, isNull);
      expect(store.finishedPurchases, isEmpty);
      expect(billing.canRestore, isTrue);
    },
  );

  test(
    'a transient verification error grants nothing and remains retryable',
    () async {
      final settings = SettingsService();
      await settings.init();
      final initialSeconds = settings.remainingSeconds;
      final store = _FakeBillingStore();
      final verifier = _FakePurchaseVerifier(shouldThrow: true);
      final billing = BillingService(
        settings,
        store: store,
        verifier: verifier,
      );
      addTearDown(() async {
        billing.dispose();
        await store.close();
      });

      await billing.init();
      final handled = _nextStatus(billing, BillingStatus.verificationError);
      store.emit([_purchase()]);
      await handled;

      expect(settings.remainingSeconds, initialSeconds);
      expect(settings.vipUntil, isNull);
      expect(store.finishedPurchases, isEmpty);
      expect(billing.canRestore, isTrue);
    },
  );
}

Future<void> _nextStatus(BillingService billing, BillingStatus expected) {
  final completer = Completer<void>();
  late VoidCallback listener;
  listener = () {
    if (billing.status == expected && !completer.isCompleted) {
      billing.removeListener(listener);
      completer.complete();
    }
  };
  billing.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 2));
}

DateTime _millisecondUtcNow() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
}

AuthoritativeEntitlementSnapshot _snapshot({
  int revision = 1,
  DateTime? vipUntil,
}) {
  return AuthoritativeEntitlementSnapshot(
    revision: revision,
    generatedAt: _millisecondUtcNow(),
    vipUntil: vipUntil,
  );
}

PurchaseDetails _purchase({
  PurchaseStatus status = PurchaseStatus.purchased,
  String productId = BillingProductIds.hourPass,
}) {
  final purchase = PurchaseDetails(
    purchaseID: 'untrusted-client-purchase-id',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local-data-must-not-grant',
      serverVerificationData: 'server-receipt-token',
      source: 'google_play',
    ),
    transactionDate: '1788912000000',
    status: status,
  )..pendingCompletePurchase = true;
  if (status == PurchaseStatus.error) {
    purchase.error = IAPError(
      source: 'test-store',
      code: 'billing_error',
      message: 'Store transaction failed.',
    );
  }
  return purchase;
}

class _ThrowingSnapshotSource extends EntitlementSnapshotSource {
  @override
  bool get isConfigured => true;

  @override
  Future<AuthoritativeEntitlementSnapshot> fetch() {
    throw const EntitlementReconciliationException(
      'Temporary snapshot failure.',
    );
  }
}

class _FakePurchaseVerifier extends PurchaseVerifier {
  _FakePurchaseVerifier({
    this.configured = true,
    this.result,
    this.shouldThrow = false,
  });

  final bool configured;
  final PurchaseVerificationResult? result;
  final bool shouldThrow;
  final List<StorePurchaseProof> proofs = [];

  @override
  bool get isConfigured => configured;

  @override
  Future<PurchaseVerificationResult> verify(StorePurchaseProof proof) async {
    proofs.add(proof);
    if (shouldThrow) {
      throw const PurchaseVerificationException('Temporary backend failure.');
    }
    return result ?? const PurchaseVerificationResult.pending();
  }
}

class _FakeBillingStore extends BillingStore {
  _FakeBillingStore({int expectedFinishes = 0})
    : _expectedFinishCount = expectedFinishes;

  final int _expectedFinishCount;
  final StreamController<List<PurchaseDetails>> _controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  final List<PurchaseDetails> finishedPurchases = [];
  final List<bool> finishedConsumableFlags = [];
  final Completer<void> _finishes = Completer<void>();

  Future<void> get expectedFinishes {
    if (_expectedFinishCount == 0 ||
        finishedPurchases.length >= _expectedFinishCount) {
      return Future<void>.value();
    }
    return _finishes.future.timeout(const Duration(seconds: 2));
  }

  void emit(List<PurchaseDetails> purchases) => _controller.add(purchases);

  Future<void> close() async {
    await _controller.close();
  }

  @override
  bool get isSupported => true;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) {
    return Future.value(
      ProductDetailsResponse(
        productDetails: [],
        notFoundIDs: identifiers.toList(),
      ),
    );
  }

  @override
  Future<bool> buyConsumable({required PurchaseParam purchaseParam}) async {
    return true;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return true;
  }

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> finishPurchase(
    PurchaseDetails purchase, {
    required bool consumable,
  }) async {
    finishedPurchases.add(purchase);
    finishedConsumableFlags.add(consumable);
    if (_expectedFinishCount > 0 &&
        finishedPurchases.length >= _expectedFinishCount &&
        !_finishes.isCompleted) {
      _finishes.complete();
    }
  }
}
