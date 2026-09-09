import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'settings_service.dart';

enum BillingStatus {
  loading,
  ready,
  purchasing,
  success,
  unavailable,
  error,
}

enum OfferKind { consumable, subscription }

class BillingOffer {
  const BillingOffer({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.descriptionKey,
    required this.fallbackPrice,
    this.product,
  });

  final String id;
  final OfferKind kind;
  final String titleKey;
  final String descriptionKey;
  final String fallbackPrice;
  final ProductDetails? product;

  String get price => product?.price ?? fallbackPrice;

  BillingOffer withProduct(ProductDetails value) {
    return BillingOffer(
      id: id,
      kind: kind,
      titleKey: titleKey,
      descriptionKey: descriptionKey,
      fallbackPrice: fallbackPrice,
      product: value,
    );
  }
}

class BillingService extends ChangeNotifier {
  BillingService(this._settings);

  static const hourPassId = 'globoverse_hour_pass';
  static const monthlyVipId = 'globoverse_vip_monthly';

  final SettingsService _settings;
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  BillingStatus _status = BillingStatus.loading;
  String? _error;
  bool _initialized = false;
  void Function()? onHourPassGranted;

  BillingStatus get status => _status;
  String? get error => _error;
  bool get isAvailable => _status != BillingStatus.unavailable;
  bool get isBusy =>
      _status == BillingStatus.loading || _status == BillingStatus.purchasing;

  List<BillingOffer> _offers = const [
    BillingOffer(
      id: hourPassId,
      kind: OfferKind.consumable,
      titleKey: 'hourPass',
      descriptionKey: 'hourPassBody',
      fallbackPrice: r'$1.99',
    ),
    BillingOffer(
      id: monthlyVipId,
      kind: OfferKind.subscription,
      titleKey: 'monthlyVip',
      descriptionKey: 'monthlyVipBody',
      fallbackPrice: r'$7.99',
    ),
  ];

  List<BillingOffer> get offers => List.unmodifiable(_offers);

  /// StoreKit 2 is the default in current in_app_purchase releases. This hook
  /// intentionally runs before any store instance is touched and remains the
  /// single place for an eventual StoreKit 1 fallback.
  static void configureStorekit() {}

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform)) {
      _status = BillingStatus.unavailable;
      notifyListeners();
      return;
    }

    _purchaseSubscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) {
        _error = error.toString();
        _status = BillingStatus.error;
        notifyListeners();
      },
    );

    try {
      final available = await _store.isAvailable();
      if (!available) {
        _status = BillingStatus.unavailable;
        notifyListeners();
        return;
      }

      final response = await _store.queryProductDetails(
        _offers.map((offer) => offer.id).toSet(),
      );
      if (response.error != null) {
        _error = response.error?.message;
      }

      final details = {for (final product in response.productDetails) product.id: product};
      _offers = _offers
          .map((offer) => details[offer.id] == null
              ? offer
              : offer.withProduct(details[offer.id]!))
          .toList(growable: false);
      _status = BillingStatus.ready;
    } catch (error) {
      _error = error.toString();
      _status = BillingStatus.error;
    }
    notifyListeners();
  }

  Future<bool> purchase(BillingOffer offer) async {
    final product = offer.product;
    if (product == null || isBusy) {
      _error = 'This product is not available from the store.';
      _status = BillingStatus.error;
      notifyListeners();
      return false;
    }

    _error = null;
    _status = BillingStatus.purchasing;
    notifyListeners();

    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final started = offer.kind == OfferKind.consumable
          ? await _store.buyConsumable(
              purchaseParam: purchaseParam,
              autoConsume: true,
            )
          : await _store.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) _status = BillingStatus.ready;
      notifyListeners();
      return started;
    } catch (error) {
      _error = error.toString();
      _status = BillingStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (_status == BillingStatus.unavailable) return;
    _status = BillingStatus.loading;
    _error = null;
    notifyListeners();
    try {
      await _store.restorePurchases();
      _status = BillingStatus.ready;
    } catch (error) {
      _error = error.toString();
      _status = BillingStatus.error;
    }
    notifyListeners();
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        _status = BillingStatus.purchasing;
        notifyListeners();
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _error = purchase.error?.message;
        _status = BillingStatus.error;
      } else if (purchase.status == PurchaseStatus.canceled) {
        _status = BillingStatus.ready;
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _deliverPurchase(purchase);
      }

      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  Future<void> _deliverPurchase(PurchaseDetails purchase) async {
    final purchaseId = purchase.purchaseID ??
        '${purchase.productID}:${purchase.transactionDate ?? 'restored'}';
    if (_settings.hasProcessedPurchase(purchaseId)) {
      _status = BillingStatus.ready;
      return;
    }

    // Production deployments should verify the receipt on a trusted backend
    // before granting an entitlement. The client-side ledger prevents an event
    // from being delivered twice while that backend is being connected.
    if (purchase.productID == hourPassId) {
      onHourPassGranted?.call();
    } else if (purchase.productID == monthlyVipId) {
      final now = DateTime.now();
      final current = _settings.vipUntil;
      final startsAt = current != null && current.isAfter(now) ? current : now;
      await _settings.setVipUntil(startsAt.add(const Duration(days: 30)));
    } else {
      return;
    }

    await _settings.markPurchaseProcessed(purchaseId);
    _status = BillingStatus.success;
  }

  void clearMessage() {
    if (_status == BillingStatus.success || _status == BillingStatus.error) {
      _status = BillingStatus.ready;
      _error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
