import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/billing_store.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

void main() {
  group('DeviceBillingStore.finishPurchase', () {
    test('manually consumes a verified Android consumable', () async {
      final completed = <PurchaseDetails>[];
      final consumed = <PurchaseDetails>[];
      final store = DeviceBillingStore(
        platformOverride: TargetPlatform.android,
        completePurchaseOverride: (purchase) async {
          completed.add(purchase);
        },
        consumePurchaseOverride: (purchase) async {
          consumed.add(purchase);
          return BillingResponse.ok;
        },
      );
      final purchase = _purchase();

      await store.finishPurchase(purchase, consumable: true);

      expect(consumed, hasLength(1));
      expect(consumed.single, same(purchase));
      expect(completed, isEmpty);
    });

    test('rejects a failed Android consumption response', () async {
      final store = DeviceBillingStore(
        platformOverride: TargetPlatform.android,
        consumePurchaseOverride: (_) async => BillingResponse.error,
      );

      await expectLater(
        store.finishPurchase(_purchase(), consumable: true),
        throwsA(isA<StateError>()),
      );
    });

    test('completes rather than consumes a non-consumable event', () async {
      final completed = <PurchaseDetails>[];
      var consumeCalls = 0;
      final store = DeviceBillingStore(
        platformOverride: TargetPlatform.android,
        completePurchaseOverride: (purchase) async {
          completed.add(purchase);
        },
        consumePurchaseOverride: (_) async {
          consumeCalls += 1;
          return BillingResponse.ok;
        },
      );
      final purchase = _purchase();

      await store.finishPurchase(purchase, consumable: false);

      expect(completed, hasLength(1));
      expect(completed.single, same(purchase));
      expect(consumeCalls, 0);
    });

    test('completes an Apple consumable through the store', () async {
      final completed = <PurchaseDetails>[];
      var consumeCalls = 0;
      final store = DeviceBillingStore(
        platformOverride: TargetPlatform.iOS,
        completePurchaseOverride: (purchase) async {
          completed.add(purchase);
        },
        consumePurchaseOverride: (_) async {
          consumeCalls += 1;
          return BillingResponse.ok;
        },
      );
      final purchase = _purchase();

      await store.finishPurchase(purchase, consumable: true);

      expect(completed, hasLength(1));
      expect(completed.single, same(purchase));
      expect(consumeCalls, 0);
    });

    test('does not complete a transaction that is already finished', () async {
      var completeCalls = 0;
      final store = DeviceBillingStore(
        platformOverride: TargetPlatform.iOS,
        completePurchaseOverride: (_) async {
          completeCalls += 1;
        },
      );
      final purchase = _purchase()..pendingCompletePurchase = false;

      await store.finishPurchase(purchase, consumable: false);

      expect(completeCalls, 0);
    });
  });
}

PurchaseDetails _purchase() {
  return PurchaseDetails(
    purchaseID: 'purchase-1',
    productID: 'globoverse_hour_pass',
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local-data',
      serverVerificationData: 'server-data',
      source: 'test-store',
    ),
    transactionDate: '1700000000000',
    status: PurchaseStatus.purchased,
  )..pendingCompletePurchase = true;
}
