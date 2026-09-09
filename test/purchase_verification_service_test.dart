import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/purchase_verification_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends server receipt data and accepts an exact hour grant', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return _jsonResponse({
        'status': 'verified',
        'verificationId': 'google:order-42',
        'productId': BillingProductIds.hourPass,
        'entitlement': {'type': 'session_time', 'seconds': 3600},
        'snapshot': {
          'revision': 7,
          'generatedAt': '2026-09-09T00:00:00.000Z',
          'vipUntil': null,
        },
      });
    });
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com/v1/',
      apiToken: 'short-lived-token',
      now: () => DateTime.utc(2026, 9, 9),
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    final result = await verifier.verify(_proof());

    expect(result.decision, PurchaseVerificationDecision.verified);
    expect(result.grant?.verificationId, 'google:order-42');
    expect(result.grant?.kind, VerifiedEntitlementKind.sessionTime);
    expect(result.grant?.sessionSeconds, 3600);
    expect(result.snapshot?.revision, 7);
    expect(result.snapshot?.vipUntil, isNull);
    expect(
      capturedRequest.url,
      Uri.parse('https://billing.example.com/v1/billing/verify'),
    );
    expect(capturedRequest.followRedirects, isFalse);
    expect(
      capturedRequest.headers.values,
      contains('Bearer short-lived-token'),
    );
    expect(capturedRequest.headers.values, contains('purchase-client-42'));

    final body = Map<String, dynamic>.from(
      jsonDecode(capturedRequest.body) as Map,
    );
    expect(body['productId'], BillingProductIds.hourPass);
    expect(body['purchaseId'], 'purchase-client-42');
    expect(body['source'], 'google_play');
    expect(body['verificationData'], 'server-receipt-token');
    expect(body['isRestore'], isFalse);
    expect(body.containsKey('localVerificationData'), isFalse);
  });

  test('accepts only a bounded server-authored VIP expiry', () async {
    final client = MockClient(
      (_) async => _jsonResponse({
        'status': 'verified',
        'verificationId': 'apple:transaction-7',
        'productId': BillingProductIds.monthlyVip,
        'entitlement': {'type': 'vip', 'expiresAt': '2026-10-09T00:00:00.000Z'},
        'snapshot': {
          'revision': 8,
          'generatedAt': '2026-09-09T00:00:00.000Z',
          'vipUntil': '2026-10-09T00:00:00.000Z',
        },
      }),
    );
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
      now: () => DateTime.utc(2026, 9, 9),
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    final result = await verifier.verify(
      _proof(productId: BillingProductIds.monthlyVip, source: 'app_store'),
    );

    expect(result.decision, PurchaseVerificationDecision.verified);
    expect(result.grant?.kind, VerifiedEntitlementKind.vip);
    expect(result.grant?.vipUntil, DateTime.utc(2026, 10, 9));
  });

  test('rejects a VIP grant that disagrees with its snapshot', () async {
    final client = MockClient(
      (_) async => _jsonResponse({
        'status': 'verified',
        'verificationId': 'apple:mismatched-snapshot',
        'productId': BillingProductIds.monthlyVip,
        'entitlement': {'type': 'vip', 'expiresAt': '2026-10-09T00:00:00.000Z'},
        'snapshot': {
          'revision': 9,
          'generatedAt': '2026-09-09T00:00:00.000Z',
          'vipUntil': '2026-10-08T00:00:00.000Z',
        },
      }),
    );
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
      now: () => DateTime.utc(2026, 9, 9),
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    await expectLater(
      verifier.verify(
        _proof(productId: BillingProductIds.monthlyVip, source: 'app_store'),
      ),
      throwsA(isA<PurchaseVerificationException>()),
    );
  });

  test('rejects a VIP expiry outside the allowed server window', () async {
    final client = MockClient(
      (_) async => _jsonResponse({
        'status': 'verified',
        'verificationId': 'apple:transaction-too-long',
        'productId': BillingProductIds.monthlyVip,
        'entitlement': {'type': 'vip', 'expiresAt': '2027-09-09T00:00:00.000Z'},
        'snapshot': {
          'revision': 9,
          'generatedAt': '2026-09-09T00:00:00.000Z',
          'vipUntil': '2027-09-09T00:00:00.000Z',
        },
      }),
    );
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
      now: () => DateTime.utc(2026, 9, 9),
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    await expectLater(
      verifier.verify(
        _proof(productId: BillingProductIds.monthlyVip, source: 'app_store'),
      ),
      throwsA(isA<PurchaseVerificationException>()),
    );
  });

  test('rejects a mismatched or malformed verified entitlement', () async {
    final client = MockClient(
      (_) async => _jsonResponse({
        'status': 'verified',
        'verificationId': 'server-grant-1',
        'productId': BillingProductIds.monthlyVip,
        'entitlement': {'type': 'session_time', 'seconds': 999999},
        'snapshot': {
          'revision': 10,
          'generatedAt': '2026-09-09T00:00:00.000Z',
          'vipUntil': null,
        },
      }),
    );
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
      now: () => DateTime.utc(2026, 9, 9),
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    await expectLater(
      verifier.verify(_proof()),
      throwsA(isA<PurchaseVerificationException>()),
    );
  });

  test(
    'rejects a verified response without an authoritative snapshot',
    () async {
      final client = MockClient(
        (_) async => _jsonResponse({
          'status': 'verified',
          'verificationId': 'google:missing-snapshot',
          'productId': BillingProductIds.hourPass,
          'entitlement': {'type': 'session_time', 'seconds': 3600},
        }),
      );
      final verifier = HttpPurchaseVerifier(
        client: client,
        endpoint: 'https://billing.example.com',
        apiToken: 'short-lived-token',
        now: () => DateTime.utc(2026, 9, 9),
      );
      addTearDown(() {
        verifier.close();
        client.close();
      });

      await expectLater(
        verifier.verify(_proof()),
        throwsA(isA<PurchaseVerificationException>()),
      );
    },
  );

  test('enforces the request limit on UTF-8 bytes', () async {
    final client = MockClient((_) async {
      fail('An oversized verification request must not be sent.');
    });
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });
    final multibyteReceipt = List.filled(300000, '😀').join();

    await expectLater(
      verifier.verify(_proof(serverVerificationData: multibyteReceipt)),
      throwsA(isA<PurchaseVerificationException>()),
    );
  });

  test('rejects an oversized verification response', () async {
    final client = MockClient(
      (_) async => http.Response(List.filled(70000, 'x').join(), 200),
    );
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    await expectLater(
      verifier.verify(_proof()),
      throwsA(isA<PurchaseVerificationException>()),
    );
  });

  test('requires a credential-free HTTPS verification boundary', () async {
    final client = MockClient((_) async {
      fail('An invalid verification boundary must not receive a request.');
    });
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'http://user:secret@billing.example.com?unsafe=true',
      apiToken: 'short-lived-token',
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    expect(verifier.isConfigured, isFalse);
    await expectLater(
      verifier.verify(_proof()),
      throwsA(isA<PurchaseVerificationException>()),
    );
  });

  test('rejects an HTTPS URI without a host', () {
    final verifier = HttpPurchaseVerifier(
      endpoint: 'https:///v1',
      apiToken: 'short-lived-token',
    );
    addTearDown(verifier.close);

    expect(verifier.isConfigured, isFalse);
  });

  test('requires an authenticated verification boundary', () {
    final verifier = HttpPurchaseVerifier(
      endpoint: 'https://billing.example.com',
      apiToken: '',
    );
    addTearDown(verifier.close);

    expect(verifier.isConfigured, isFalse);
  });

  test('a definitive backend rejection contains no grant', () async {
    final client = MockClient(
      (_) async => _jsonResponse({'status': 'rejected'}),
    );
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    final result = await verifier.verify(_proof());

    expect(result.decision, PurchaseVerificationDecision.rejected);
    expect(result.grant, isNull);
    expect(result.snapshot, isNull);
  });

  testWidgets('times out with an abort signal and ignores a late response', (
    tester,
  ) async {
    final serverResponse = Completer<http.StreamedResponse>();
    late http.AbortableRequest capturedRequest;
    final client = MockClient.streaming((request, _) {
      capturedRequest = request as http.AbortableRequest;
      return serverResponse.future;
    });
    final verifier = HttpPurchaseVerifier(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'short-lived-token',
      requestTimeout: const Duration(seconds: 1),
    );
    addTearDown(() {
      verifier.close();
      client.close();
    });

    final verification = expectLater(
      verifier.verify(_proof()),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await verification;
    await expectLater(capturedRequest.abortTrigger, completes);

    if (!serverResponse.isCompleted) {
      serverResponse.complete(_streamedJsonResponse({'status': 'rejected'}));
      await tester.pump();
    }
  });
}

StorePurchaseProof _proof({
  String productId = BillingProductIds.hourPass,
  String source = 'google_play',
  String serverVerificationData = 'server-receipt-token',
}) {
  return StorePurchaseProof(
    productId: productId,
    purchaseId: 'purchase-client-42',
    transactionDate: '1788912000000',
    source: source,
    serverVerificationData: serverVerificationData,
    isRestore: false,
  );
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

http.StreamedResponse _streamedJsonResponse(Map<String, Object?> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    200,
    contentLength: bytes.length,
    headers: const {'content-type': 'application/json'},
  );
}
