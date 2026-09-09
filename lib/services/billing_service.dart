import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_store.dart';
import 'purchase_verification_service.dart';
import 'settings_service.dart';

enum BillingStatus {
  loading,
  ready,
  purchasing,
  verifying,
  success,
  unavailable,
  productsUnavailable,
  verificationRequired,
  verificationPending,
  verificationFailed,
  verificationError,
  error,
}

enum OfferKind { consumable, subscription }

class BillingOffer {
  const BillingOffer({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.descriptionKey,
    required this.unavailablePrice,
    this.product,
  });

  final String id;
  final OfferKind kind;
  final String titleKey;
  final String descriptionKey;
  final String unavailablePrice;
  final ProductDetails? product;

  String get price => product?.price ?? unavailablePrice;

  BillingOffer withProduct(ProductDetails value) {
    return BillingOffer(
      id: id,
      kind: kind,
      titleKey: titleKey,
      descriptionKey: descriptionKey,
      unavailablePrice: unavailablePrice,
      product: value,
    );
  }
}

enum _DeliveryOutcome { verified, rejected, retry }

class BillingService extends ChangeNotifier {
  BillingService(
    this._settings, {
    BillingStore? store,
    PurchaseVerifier? verifier,
  }) : _store = store ?? DeviceBillingStore(),
       _verifier = verifier ?? HttpPurchaseVerifier(),
       _ownsVerifier = verifier == null;

  static const hourPassId = BillingProductIds.hourPass;
  static const monthlyVipId = BillingProductIds.monthlyVip;
  static const _maximumFinishedTransactions = 256;

  final SettingsService _settings;
  final BillingStore _store;
  final PurchaseVerifier _verifier;
  final bool _ownsVerifier;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _purchaseQueue = Future<void>.value();
  final Set<String> _finishedStoreTransactions = {};

  BillingStatus _status = BillingStatus.loading;
  String? _error;
  bool _initialized = false;
  bool _isRestoring = false;
  bool _isDisposed = false;
  void Function()? onEntitlementsChanged;
  Future<void> Function()? onReconciliationRequested;

  BillingStatus get status => _status;
  String? get error => _error;
  bool get isAvailable => _status != BillingStatus.unavailable;
  bool get isVerificationConfigured => _verifier.isConfigured;
  bool get isRestoring => _isRestoring;
  bool get isHourPassCapacityReached => !_settings.canAcceptSessionGrant(3600);
  bool get isBusy =>
      _isRestoring ||
      _status == BillingStatus.loading ||
      _status == BillingStatus.purchasing ||
      _status == BillingStatus.verifying;
  bool get canPurchase =>
      _verifier.isConfigured &&
      (_status == BillingStatus.ready ||
          _status == BillingStatus.success ||
          _status == BillingStatus.productsUnavailable ||
          _status == BillingStatus.error);
  bool get canRestore =>
      _verifier.isConfigured &&
      !isBusy &&
      _status != BillingStatus.unavailable &&
      _status != BillingStatus.verificationRequired;

  bool canPurchaseOffer(BillingOffer offer) {
    return canPurchase &&
        offer.product != null &&
        (offer.id != hourPassId || _settings.canAcceptSessionGrant(3600));
  }

  List<BillingOffer> _offers = const [
    BillingOffer(
      id: hourPassId,
      kind: OfferKind.consumable,
      titleKey: 'hourPass',
      descriptionKey: 'hourPassBody',
      unavailablePrice: '—',
    ),
    BillingOffer(
      id: monthlyVipId,
      kind: OfferKind.subscription,
      titleKey: 'monthlyVip',
      descriptionKey: 'monthlyVipBody',
      unavailablePrice: '—',
    ),
  ];

  List<BillingOffer> get offers => List.unmodifiable(_offers);

  /// StoreKit 2 is the default in current in_app_purchase releases. This hook
  /// intentionally runs before any store instance is touched and remains the
  /// single place for an eventual StoreKit 1 fallback.
  static void configureStorekit() {}

  Future<void> init() async {
    if (_initialized || _isDisposed) return;
    _initialized = true;

    if (!_store.isSupported) {
      _status = BillingStatus.unavailable;
      _notify();
      return;
    }

    _purchaseSubscription = _store.purchaseStream.listen(
      _queuePurchases,
      onError: (Object error) {
        _error = error.toString();
        _status = BillingStatus.error;
        _notify();
      },
    );

    try {
      final available = await _store.isAvailable();
      if (!available) {
        _status = BillingStatus.unavailable;
        _notify();
        return;
      }

      final response = await _store.queryProductDetails(
        _offers.map((offer) => offer.id).toSet(),
      );
      final details = {
        for (final product in response.productDetails) product.id: product,
      };
      _offers = _offers
          .map(
            (offer) => details[offer.id] == null
                ? offer
                : offer.withProduct(details[offer.id]!),
          )
          .toList(growable: false);

      if (!_verifier.isConfigured) {
        _error = null;
        _status = BillingStatus.verificationRequired;
      } else if (response.error != null) {
        _error = response.error?.message;
        _status = BillingStatus.error;
      } else if (response.notFoundIDs.isNotEmpty &&
          _status == BillingStatus.loading) {
        _error = null;
        _status = BillingStatus.productsUnavailable;
      } else if (_status == BillingStatus.loading) {
        _status = BillingStatus.ready;
      }
    } catch (error) {
      _error = error.toString();
      _status = BillingStatus.error;
    }
    _notify();
  }

  Future<bool> purchase(BillingOffer offer) async {
    if (!_verifier.isConfigured) {
      _error = null;
      _status = BillingStatus.verificationRequired;
      _notify();
      return false;
    }

    final product = offer.product;
    final isCurrentOffer = _offers.any(
      (candidate) =>
          candidate.id == offer.id && identical(candidate.product, product),
    );
    if (!canPurchaseOffer(offer) ||
        product == null ||
        product.id != offer.id ||
        !BillingProductIds.supported.contains(offer.id) ||
        !isCurrentOffer) {
      _error = 'This product is not available from the store.';
      _status = BillingStatus.error;
      _notify();
      return false;
    }

    _error = null;
    _status = BillingStatus.purchasing;
    _notify();

    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final started = offer.kind == OfferKind.consumable
          ? await _store.buyConsumable(purchaseParam: purchaseParam)
          : await _store.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) _status = BillingStatus.ready;
      _notify();
      return started;
    } catch (error) {
      _error = error.toString();
      _status = BillingStatus.error;
      _notify();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (!_verifier.isConfigured) {
      _error = null;
      _status = BillingStatus.verificationRequired;
      _notify();
      return;
    }
    if (!canRestore) return;

    final idleStatus = _status == BillingStatus.productsUnavailable
        ? BillingStatus.productsUnavailable
        : BillingStatus.ready;
    _isRestoring = true;
    _status = BillingStatus.loading;
    _error = null;
    _notify();
    try {
      await _store.restorePurchases();
      await onReconciliationRequested?.call();
      if (_status == BillingStatus.loading) _status = idleStatus;
    } catch (error) {
      _error = error.toString();
      _status = BillingStatus.error;
    } finally {
      _isRestoring = false;
    }
    _notify();
  }

  void _queuePurchases(List<PurchaseDetails> purchases) {
    _purchaseQueue = _purchaseQueue.then((_) async {
      try {
        await _handlePurchases(purchases);
      } catch (error) {
        _error = error.toString();
        _status = BillingStatus.error;
        _notify();
      }
    });
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      var shouldFinish = false;
      var shouldConsume = false;
      final isConsumableProduct = purchase.productID == hourPassId;
      final completionKey = _completionKey(purchase);

      if (purchase.status == PurchaseStatus.pending) {
        _error = null;
        _status = BillingStatus.purchasing;
        _notify();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _error = purchase.error?.message;
        _status = BillingStatus.error;
        shouldFinish = true;
      } else if (purchase.status == PurchaseStatus.canceled) {
        _error = null;
        _status = _verifier.isConfigured
            ? BillingStatus.ready
            : BillingStatus.verificationRequired;
        shouldFinish = true;
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _error = null;
        _status = BillingStatus.verifying;
        _notify();
        final outcome = await _deliverPurchase(purchase);
        shouldFinish = outcome != _DeliveryOutcome.retry;
        shouldConsume = shouldFinish && isConsumableProduct;
      }

      if (shouldFinish &&
          (purchase.pendingCompletePurchase || shouldConsume) &&
          (completionKey == null ||
              !_finishedStoreTransactions.contains(completionKey))) {
        await _store.finishPurchase(purchase, consumable: shouldConsume);
        if (completionKey != null) {
          _rememberFinishedTransaction(completionKey);
        }
        purchase.pendingCompletePurchase = false;
      }
      _notify();
    }
  }

  Future<_DeliveryOutcome> _deliverPurchase(PurchaseDetails purchase) async {
    if (!_verifier.isConfigured) {
      _status = BillingStatus.verificationRequired;
      return _DeliveryOutcome.retry;
    }
    if (!BillingProductIds.supported.contains(purchase.productID)) {
      _status = BillingStatus.verificationFailed;
      return _DeliveryOutcome.rejected;
    }

    try {
      final result = await _verifier.verify(
        StorePurchaseProof(
          productId: purchase.productID,
          purchaseId: purchase.purchaseID,
          transactionDate: purchase.transactionDate,
          source: purchase.verificationData.source,
          serverVerificationData:
              purchase.verificationData.serverVerificationData,
          isRestore: purchase.status == PurchaseStatus.restored,
        ),
      );

      switch (result.decision) {
        case PurchaseVerificationDecision.rejected:
          _status = BillingStatus.verificationFailed;
          return _DeliveryOutcome.rejected;
        case PurchaseVerificationDecision.pending:
          _status = BillingStatus.verificationPending;
          return _DeliveryOutcome.retry;
        case PurchaseVerificationDecision.verified:
          await _settings.applyVerifiedPurchaseGrant(
            result.grant!,
            result.snapshot!,
          );
          _notifyEntitlementsChanged();
          _status = BillingStatus.success;
          return _DeliveryOutcome.verified;
      }
    } catch (_) {
      _error = null;
      _status = BillingStatus.verificationError;
      return _DeliveryOutcome.retry;
    }
  }

  void _notifyEntitlementsChanged() {
    try {
      onEntitlementsChanged?.call();
    } catch (_) {
      // Entitlement persistence succeeded; observer failures must not leave a
      // verified store transaction unfinished.
    }
  }

  void _rememberFinishedTransaction(String key) {
    _finishedStoreTransactions.add(key);
    while (_finishedStoreTransactions.length > _maximumFinishedTransactions) {
      _finishedStoreTransactions.remove(_finishedStoreTransactions.first);
    }
  }

  String? _completionKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID;
    final source = purchase.verificationData.source;
    if (purchaseId == null ||
        purchaseId.isEmpty ||
        purchaseId.length > 500 ||
        source.isEmpty ||
        source.length > 100 ||
        purchase.productID.length > 100) {
      return null;
    }
    return '$source:${purchase.productID}:$purchaseId';
  }

  void clearMessage() {
    if (_status == BillingStatus.success ||
        _status == BillingStatus.error ||
        _status == BillingStatus.verificationFailed ||
        _status == BillingStatus.verificationError ||
        _status == BillingStatus.verificationPending) {
      _status = _verifier.isConfigured
          ? BillingStatus.ready
          : BillingStatus.verificationRequired;
      _error = null;
      _notify();
    }
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    onEntitlementsChanged = null;
    onReconciliationRequested = null;
    final subscription = _purchaseSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    if (_ownsVerifier) _verifier.close();
    super.dispose();
  }
}
