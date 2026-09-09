import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'entitlement_models.dart';

class BillingProductIds {
  const BillingProductIds._();

  static const hourPass = 'globoverse_hour_pass';
  static const monthlyVip = 'globoverse_vip_monthly';
  static const supported = {hourPass, monthlyVip};
}

enum VerifiedEntitlementKind { sessionTime, vip }

class StorePurchaseProof {
  const StorePurchaseProof({
    required this.productId,
    required this.purchaseId,
    required this.transactionDate,
    required this.source,
    required this.serverVerificationData,
    required this.isRestore,
  });

  final String productId;
  final String? purchaseId;
  final String? transactionDate;
  final String source;
  final String serverVerificationData;
  final bool isRestore;
}

class VerifiedPurchaseGrant {
  const VerifiedPurchaseGrant._({
    required this.verificationId,
    required this.productId,
    required this.kind,
    this.sessionSeconds,
    this.vipUntil,
  });

  factory VerifiedPurchaseGrant.sessionTime({
    required String verificationId,
    required String productId,
    required int seconds,
  }) {
    return VerifiedPurchaseGrant._(
      verificationId: verificationId,
      productId: productId,
      kind: VerifiedEntitlementKind.sessionTime,
      sessionSeconds: seconds,
    );
  }

  factory VerifiedPurchaseGrant.vip({
    required String verificationId,
    required String productId,
    required DateTime vipUntil,
  }) {
    return VerifiedPurchaseGrant._(
      verificationId: verificationId,
      productId: productId,
      kind: VerifiedEntitlementKind.vip,
      vipUntil: vipUntil,
    );
  }

  final String verificationId;
  final String productId;
  final VerifiedEntitlementKind kind;
  final int? sessionSeconds;
  final DateTime? vipUntil;
}

enum PurchaseVerificationDecision { verified, rejected, pending }

class PurchaseVerificationResult {
  const PurchaseVerificationResult._(this.decision, this.grant, this.snapshot);

  const PurchaseVerificationResult.rejected()
    : this._(PurchaseVerificationDecision.rejected, null, null);

  const PurchaseVerificationResult.pending()
    : this._(PurchaseVerificationDecision.pending, null, null);

  const PurchaseVerificationResult.verified(
    VerifiedPurchaseGrant grant,
    AuthoritativeEntitlementSnapshot snapshot,
  ) : this._(PurchaseVerificationDecision.verified, grant, snapshot);

  final PurchaseVerificationDecision decision;
  final VerifiedPurchaseGrant? grant;
  final AuthoritativeEntitlementSnapshot? snapshot;
}

abstract class PurchaseVerifier {
  bool get isConfigured;

  Future<PurchaseVerificationResult> verify(StorePurchaseProof proof);

  void close() {}
}

class PurchaseVerificationException implements Exception {
  const PurchaseVerificationException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseVerificationException: $message';
}

class HttpPurchaseVerifier extends PurchaseVerifier {
  HttpPurchaseVerifier({
    http.Client? client,
    String? endpoint,
    String? apiToken,
    this.requestTimeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : assert(requestTimeout > Duration.zero),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoint = (endpoint ?? _configuredEndpoint).trim().replaceFirst(
         RegExp(r'/+$'),
         '',
       ),
       _apiToken = (apiToken ?? _configuredApiToken).trim(),
       _now = now ?? DateTime.now;

  static const _configuredEndpoint = String.fromEnvironment(
    'GLOBOVERSE_BILLING_API_URL',
  );
  static const _configuredApiToken = String.fromEnvironment(
    'GLOBOVERSE_API_TOKEN',
  );
  static const _maximumReceiptCharacters = 1024 * 1024;
  static const _maximumRequestBytes = 1024 * 1024;
  static const _maximumResponseBytes = 64 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final String _endpoint;
  final String _apiToken;
  final DateTime Function() _now;
  final Duration requestTimeout;

  @override
  bool get isConfigured => _validatedBaseUri != null && _hasValidToken;

  @override
  Future<PurchaseVerificationResult> verify(StorePurchaseProof proof) async {
    if (!isConfigured) {
      throw const PurchaseVerificationException(
        'Authenticated purchase verification is not configured.',
      );
    }
    _validateProof(proof);

    final encodedBody = utf8.encode(
      jsonEncode({
        'productId': proof.productId,
        'purchaseId': proof.purchaseId,
        'transactionDate': proof.transactionDate,
        'source': proof.source,
        'verificationData': proof.serverVerificationData,
        'isRestore': proof.isRestore,
      }),
    );
    if (encodedBody.length > _maximumRequestBytes) {
      throw const PurchaseVerificationException(
        'The purchase verification request is too large.',
      );
    }

    final abort = Completer<void>();
    final idempotencyKey = _idempotencyKey(proof.purchaseId);
    final request =
        http.AbortableRequest(
            'POST',
            _uri('/billing/verify'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiToken',
            if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
          })
          ..bodyBytes = encodedBody;

    try {
      return await _sendAndParse(request, proof).timeout(
        requestTimeout,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw TimeoutException(
            'Purchase verification timed out.',
            requestTimeout,
          );
        },
      );
    } on PurchaseVerificationException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on FormatException catch (error) {
      throw PurchaseVerificationException(error.message.toString());
    } on http.ClientException {
      rethrow;
    } catch (_) {
      throw const PurchaseVerificationException(
        'Purchase verification failed.',
      );
    }
  }

  Future<PurchaseVerificationResult> _sendAndParse(
    http.AbortableRequest request,
    StorePurchaseProof proof,
  ) async {
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await _cancelResponse(response);
      throw PurchaseVerificationException(
        'Verification server returned ${response.statusCode}.',
      );
    }
    if (response.contentLength != null &&
        response.contentLength! > _maximumResponseBytes) {
      await _cancelResponse(response);
      throw const PurchaseVerificationException(
        'Verification response is too large.',
      );
    }

    final body = BytesBuilder(copy: false);
    var byteCount = 0;
    await for (final chunk in response.stream) {
      byteCount += chunk.length;
      if (byteCount > _maximumResponseBytes) {
        throw const PurchaseVerificationException(
          'Verification response is too large.',
        );
      }
      body.add(chunk);
    }

    final decoded = jsonDecode(utf8.decode(body.takeBytes()));
    if (decoded is! Map) {
      throw const PurchaseVerificationException(
        'Verification response is invalid.',
      );
    }
    return _parseResult(Map<String, dynamic>.from(decoded), proof);
  }

  PurchaseVerificationResult _parseResult(
    Map<String, dynamic> payload,
    StorePurchaseProof proof,
  ) {
    final status = payload['status'];
    if (status == 'rejected') {
      return const PurchaseVerificationResult.rejected();
    }
    if (status == 'pending') {
      return const PurchaseVerificationResult.pending();
    }
    if (status != 'verified') {
      throw const PurchaseVerificationException(
        'Verification status is invalid.',
      );
    }

    final verificationId = _parseVerificationId(payload['verificationId']);
    final productId = payload['productId'];
    final entitlement = payload['entitlement'];
    final snapshot = _parseSnapshot(payload['snapshot']);
    if (verificationId == null ||
        productId != proof.productId ||
        entitlement is! Map ||
        snapshot == null) {
      throw const PurchaseVerificationException(
        'Verified purchase response does not match the request.',
      );
    }

    if (proof.productId == BillingProductIds.hourPass &&
        entitlement['type'] == 'session_time' &&
        entitlement['seconds'] == 3600) {
      return PurchaseVerificationResult.verified(
        VerifiedPurchaseGrant.sessionTime(
          verificationId: verificationId,
          productId: proof.productId,
          seconds: 3600,
        ),
        snapshot,
      );
    }

    if (proof.productId == BillingProductIds.monthlyVip &&
        entitlement['type'] == 'vip') {
      final vipUntil = _parseVipUntil(entitlement['expiresAt']);
      if (vipUntil != null && vipUntil == snapshot.vipUntil) {
        return PurchaseVerificationResult.verified(
          VerifiedPurchaseGrant.vip(
            verificationId: verificationId,
            productId: proof.productId,
            vipUntil: vipUntil,
          ),
          snapshot,
        );
      }
    }

    throw const PurchaseVerificationException(
      'Verified entitlement is invalid for this product.',
    );
  }

  void _validateProof(StorePurchaseProof proof) {
    if (!BillingProductIds.supported.contains(proof.productId)) {
      throw const PurchaseVerificationException(
        'The purchase product is not supported.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(proof.source)) {
      throw const PurchaseVerificationException(
        'The purchase source is invalid.',
      );
    }
    if (proof.serverVerificationData.isEmpty ||
        proof.serverVerificationData.length > _maximumReceiptCharacters) {
      throw const PurchaseVerificationException(
        'The server verification data is invalid.',
      );
    }
    if (!_isOptionalBoundedString(proof.purchaseId, 500) ||
        !_isOptionalBoundedString(proof.transactionDate, 100)) {
      throw const PurchaseVerificationException(
        'The purchase metadata is invalid.',
      );
    }
  }

  bool _isOptionalBoundedString(String? value, int maximumLength) {
    if (value == null) return true;
    return value.isNotEmpty &&
        value.length <= maximumLength &&
        !RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value);
  }

  String? _parseVerificationId(Object? value) {
    if (value is! String || value.length > 200) return null;
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value)
        ? value
        : null;
  }

  AuthoritativeEntitlementSnapshot? _parseSnapshot(Object? value) {
    if (value is! Map ||
        value.length != 3 ||
        !value.containsKey('revision') ||
        !value.containsKey('generatedAt') ||
        !value.containsKey('vipUntil')) {
      return null;
    }
    final revision = value['revision'];
    final generatedAt = _parseUtcTimestamp(value['generatedAt']);
    final vipValue = value['vipUntil'];
    final vipUntil = vipValue == null ? null : _parseUtcTimestamp(vipValue);
    if (revision is! int ||
        revision <= 0 ||
        revision > maximumEntitlementRevision ||
        generatedAt == null ||
        (vipValue != null && vipUntil == null)) {
      return null;
    }

    final now = _now().toUtc();
    if (generatedAt.isBefore(now.subtract(const Duration(hours: 1))) ||
        generatedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      return null;
    }
    if (vipUntil != null &&
        (!vipUntil.isAfter(now) ||
            !vipUntil.isAfter(generatedAt) ||
            vipUntil.isAfter(generatedAt.add(maximumVerifiedVipHorizon)))) {
      return null;
    }
    return AuthoritativeEntitlementSnapshot(
      revision: revision,
      generatedAt: generatedAt,
      vipUntil: vipUntil,
    );
  }

  DateTime? _parseUtcTimestamp(Object? value) {
    if (value is! String || value.length > 64) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{3})?Z$',
    ).firstMatch(value);
    if (match == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        !parsed.isUtc ||
        parsed.year != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!) ||
        parsed.hour != int.parse(match.group(4)!) ||
        parsed.minute != int.parse(match.group(5)!) ||
        parsed.second != int.parse(match.group(6)!)) {
      return null;
    }
    return parsed;
  }

  DateTime? _parseVipUntil(Object? value) {
    final parsed = _parseUtcTimestamp(value);
    if (parsed == null) return null;
    final now = _now().toUtc();
    if (!parsed.isAfter(now) ||
        parsed.isAfter(now.add(maximumVerifiedVipHorizon))) {
      return null;
    }
    return parsed;
  }

  String? _idempotencyKey(String? purchaseId) {
    if (purchaseId == null || purchaseId.length > 200) return null;
    return RegExp(r'^[\x21-\x7E]+$').hasMatch(purchaseId) ? purchaseId : null;
  }

  bool get _hasValidToken =>
      _apiToken.isNotEmpty &&
      _apiToken.length <= 4096 &&
      !RegExp(r'[\u0000-\u001F\u007F]').hasMatch(_apiToken);

  Uri? get _validatedBaseUri {
    final base = Uri.tryParse(_endpoint);
    if (base == null ||
        base.scheme != 'https' ||
        !base.hasAuthority ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return null;
    }
    return base;
  }

  Uri _uri(String path) {
    if (_validatedBaseUri == null) {
      throw const PurchaseVerificationException(
        'The purchase verification API URL is invalid.',
      );
    }
    return Uri.parse('$_endpoint$path');
  }

  Future<void> _cancelResponse(http.StreamedResponse response) async {
    final subscription = response.stream.listen((_) {});
    await subscription.cancel();
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
