import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

abstract class BillingStore {
  bool get isSupported;
  Stream<List<PurchaseDetails>> get purchaseStream;

  Future<bool> isAvailable();

  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers);

  Future<bool> buyConsumable({required PurchaseParam purchaseParam});

  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam});

  Future<void> restorePurchases();

  Future<void> finishPurchase(
    PurchaseDetails purchase, {
    required bool consumable,
  });
}

typedef StorePurchaseCompleter =
    Future<void> Function(PurchaseDetails purchase);
typedef AndroidPurchaseConsumer =
    Future<BillingResponse> Function(PurchaseDetails purchase);

class DeviceBillingStore extends BillingStore {
  DeviceBillingStore({
    InAppPurchase? store,
    TargetPlatform? platformOverride,
    StorePurchaseCompleter? completePurchaseOverride,
    AndroidPurchaseConsumer? consumePurchaseOverride,
  }) : _injectedStore = store,
       _platform = platformOverride ?? defaultTargetPlatform,
       _completePurchaseOverride = completePurchaseOverride,
       _consumePurchaseOverride = consumePurchaseOverride;

  final InAppPurchase? _injectedStore;
  final TargetPlatform _platform;
  final StorePurchaseCompleter? _completePurchaseOverride;
  final AndroidPurchaseConsumer? _consumePurchaseOverride;

  InAppPurchase get _store => _injectedStore ?? InAppPurchase.instance;

  @override
  bool get isSupported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(_platform);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _store.purchaseStream;

  @override
  Future<bool> isAvailable() => _store.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> identifiers) {
    return _store.queryProductDetails(identifiers);
  }

  @override
  Future<bool> buyConsumable({required PurchaseParam purchaseParam}) {
    return _store.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: false,
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) {
    return _store.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> restorePurchases() => _store.restorePurchases();

  @override
  Future<void> finishPurchase(
    PurchaseDetails purchase, {
    required bool consumable,
  }) async {
    if (consumable && _platform == TargetPlatform.android) {
      final override = _consumePurchaseOverride;
      final response = override != null
          ? await override(purchase)
          : await _consumeAndroidPurchase(purchase);
      if (response != BillingResponse.ok) {
        throw StateError('The verified purchase could not be consumed.');
      }
      return;
    }
    if (purchase.pendingCompletePurchase) {
      final override = _completePurchaseOverride;
      if (override != null) {
        await override(purchase);
      } else {
        await _store.completePurchase(purchase);
      }
    }
  }

  Future<BillingResponse> _consumeAndroidPurchase(
    PurchaseDetails purchase,
  ) async {
    final android = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final result = await android.consumePurchase(purchase);
    return result.responseCode;
  }
}
