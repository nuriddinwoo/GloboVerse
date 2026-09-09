import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/entitlement_models.dart';
import 'package:globoverse/services/entitlement_reconciliation_service.dart';
import 'package:globoverse/services/settings_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fetches an authenticated authoritative snapshot', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode({
          'status': 'ok',
          'snapshot': {
            'revision': 42,
            'generatedAt': '2026-09-09T12:00:00.000Z',
            'vipUntil': '2026-10-09T12:00:00.000Z',
          },
        }),
        200,
      );
    });
    final source = HttpEntitlementSnapshotSource(
      client: client,
      endpoint: 'https://billing.example.com/v1/',
      apiToken: 'short-lived-user-token',
      now: () => DateTime.utc(2026, 9, 9, 12),
    );
    addTearDown(() {
      source.close();
      client.close();
    });

    final snapshot = await source.fetch();

    expect(snapshot.revision, 42);
    expect(snapshot.vipUntil, DateTime.utc(2026, 10, 9, 12));
    expect(
      capturedRequest.url,
      Uri.parse('https://billing.example.com/v1/billing/entitlements'),
    );
    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.followRedirects, isFalse);
    expect(
      capturedRequest.headers.values,
      contains('Bearer short-lived-user-token'),
    );
    expect(capturedRequest.headers.values, contains('no-store'));
  });

  test('rejects a stale or malformed account snapshot', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'status': 'ok',
          'snapshot': {
            'revision': 1,
            'generatedAt': '2026-09-09T09:00:00.000Z',
            'vipUntil': null,
          },
        }),
        200,
      ),
    );
    final source = HttpEntitlementSnapshotSource(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'token',
      now: () => DateTime.utc(2026, 9, 9, 12),
    );
    addTearDown(() {
      source.close();
      client.close();
    });

    await expectLater(
      source.fetch(),
      throwsA(isA<EntitlementReconciliationException>()),
    );
  });

  test('requires both a safe HTTPS endpoint and an access token', () {
    final missingToken = HttpEntitlementSnapshotSource(
      endpoint: 'https://billing.example.com',
      apiToken: '',
    );
    final unsafeEndpoint = HttpEntitlementSnapshotSource(
      endpoint: 'http://billing.example.com',
      apiToken: 'token',
    );
    addTearDown(missingToken.close);
    addTearDown(unsafeEndpoint.close);

    expect(missingToken.isConfigured, isFalse);
    expect(unsafeEndpoint.isConfigured, isFalse);
  });

  testWidgets('timeout aborts an in-flight snapshot request', (tester) async {
    final serverResponse = Completer<http.StreamedResponse>();
    late http.AbortableRequest capturedRequest;
    final client = MockClient.streaming((request, _) {
      capturedRequest = request as http.AbortableRequest;
      return serverResponse.future;
    });
    final source = HttpEntitlementSnapshotSource(
      client: client,
      endpoint: 'https://billing.example.com',
      apiToken: 'token',
      requestTimeout: const Duration(seconds: 1),
    );
    addTearDown(() {
      source.close();
      client.close();
    });

    final fetch = expectLater(source.fetch(), throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await fetch;
    await expectLater(capturedRequest.abortTrigger, completes);

    if (!serverResponse.isCompleted) {
      serverResponse.complete(
        http.StreamedResponse(const Stream<List<int>>.empty(), 500),
      );
      await tester.pump();
    }
  });

  test(
    'reconciliation applies revocation and refreshes the session view',
    () async {
      final oldVip = _millisecondUtcNow().add(const Duration(days: 20));
      SharedPreferences.setMockInitialValues({
        'billing_security_version': 1,
        'vip_until': oldVip.millisecondsSinceEpoch,
        'entitlement_revision': 1,
        'entitlement_vip_until': oldVip.millisecondsSinceEpoch,
      });
      final settings = SettingsService();
      await settings.init();
      final generatedAt = _millisecondUtcNow();
      final source = _FakeSnapshotSource(
        snapshot: AuthoritativeEntitlementSnapshot(
          revision: 2,
          generatedAt: generatedAt,
          vipUntil: null,
        ),
      );
      expect(settings.vipUntil, oldVip);
      final service = EntitlementReconciliationService(
        settings,
        source: source,
      );
      var notifications = 0;
      service.onEntitlementsChanged = () => notifications += 1;
      addTearDown(service.dispose);

      await service.refresh();

      expect(source.fetchCount, 1);
      expect(service.status, EntitlementSyncStatus.synced);
      expect(settings.entitlementRevision, 2);
      expect(settings.vipUntil, isNull);
      expect(notifications, 1);
    },
  );

  test('concurrent refresh requests share one backend operation', () async {
    final settings = SettingsService();
    await settings.init();
    final response = Completer<AuthoritativeEntitlementSnapshot>();
    final source = _FakeSnapshotSource(response: response.future);
    final service = EntitlementReconciliationService(settings, source: source);
    addTearDown(service.dispose);

    final first = service.refresh();
    final second = service.refresh();
    expect(source.fetchCount, 1);
    response.complete(
      AuthoritativeEntitlementSnapshot(
        revision: 1,
        generatedAt: _millisecondUtcNow(),
        vipUntil: null,
      ),
    );
    await Future.wait([first, second]);

    expect(source.fetchCount, 1);
    expect(service.status, EntitlementSyncStatus.synced);
  });
}

DateTime _millisecondUtcNow() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
}

class _FakeSnapshotSource extends EntitlementSnapshotSource {
  _FakeSnapshotSource({
    this.snapshot,
    Future<AuthoritativeEntitlementSnapshot>? response,
  }) : _response = response;

  final AuthoritativeEntitlementSnapshot? snapshot;
  final Future<AuthoritativeEntitlementSnapshot>? _response;
  int fetchCount = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<AuthoritativeEntitlementSnapshot> fetch() {
    fetchCount += 1;
    final response = _response;
    if (response != null) return response;
    return Future.value(snapshot!);
  }
}
