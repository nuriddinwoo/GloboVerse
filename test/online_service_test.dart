import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/services/online_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads and normalizes a valid authenticated discovery catalog',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return _jsonResponse({
          'onlineCount': 42,
          'rooms': [
            _room('room-1', languageCodes: ['EN_us', 'tg']),
            _room('room-1'),
            _room('../unsafe'),
            {..._room('unsafe-title'), 'title': 'Line\nbreak'},
          ],
          'members': [
            _member('member-1', isOnline: false, avatarSeed: 2000000000),
            _member('member-1'),
            {..._member('missing-presence'), 'isOnline': null},
            {..._member('unsafe-name'), 'name': 'A\u202Ename'},
          ],
        });
      });
      final service = OnlineService(
        client: client,
        endpoint: 'https://api.example.com/v1/',
        apiToken: 'test-token',
        automaticRefresh: false,
      );
      addTearDown(() {
        service.dispose();
        client.close();
      });

      expect(service.isPreviewCatalog, isTrue);
      expect(service.onlineCount, 0);
      expect(service.rooms.every((room) => room.memberCount == 0), isTrue);
      expect(service.members.every((member) => !member.isOnline), isTrue);
      expect(await service.refreshDiscovery(), isTrue);

      expect(capturedRequest.method, 'GET');
      expect(capturedRequest.followRedirects, isFalse);
      expect(
        capturedRequest.url,
        Uri.parse('https://api.example.com/v1/discovery'),
      );
      expect(capturedRequest.headers.values, contains('Bearer test-token'));
      expect(capturedRequest.headers.values, contains('application/json'));
      expect(service.isPreviewCatalog, isFalse);
      expect(service.discoveryError, isNull);
      expect(service.lastRefreshedAt, isNotNull);
      expect(service.onlineCount, 42);
      expect(service.rooms, hasLength(1));
      expect(service.rooms.single.id, 'room-1');
      expect(service.rooms.single.languageCodes, ['en-us', 'tg']);
      expect(service.rooms.single.accentColor, 0xFF123ABC);
      expect(service.members, hasLength(1));
      expect(service.members.single.id, 'member-1');
      expect(service.members.single.isOnline, isFalse);
      expect(service.members.single.avatarSeed, 1000000000);
    },
  );

  test(
    'keeps the last valid catalog atomically when validation fails',
    () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          return _jsonResponse({
            'onlineCount': 7,
            'rooms': [_room('stable-room')],
            'members': [_member('stable-member')],
          });
        }
        return _jsonResponse({
          'onlineCount': 99,
          'rooms': [_room('replacement-room')],
          'members': [
            {..._member('invalid-member'), 'isOnline': 'yes'},
          ],
        });
      });
      final service = OnlineService(
        client: client,
        endpoint: 'https://api.example.com',
        automaticRefresh: false,
      );
      addTearDown(() {
        service.dispose();
        client.close();
      });

      expect(await service.refreshDiscovery(), isTrue);
      final refreshedAt = service.lastRefreshedAt;

      expect(await service.refreshDiscovery(), isFalse);
      expect(service.isPreviewCatalog, isFalse);
      expect(service.onlineCount, 7);
      expect(service.rooms.single.id, 'stable-room');
      expect(service.members.single.id, 'stable-member');
      expect(service.lastRefreshedAt, refreshedAt);
      expect(service.discoveryError, contains('no valid members'));
    },
  );

  test('uses an ETag and accepts a not-modified catalog response', () async {
    final requests = <http.Request>[];
    var requestCount = 0;
    final client = MockClient((request) async {
      requests.add(request);
      requestCount += 1;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode({
            'onlineCount': 8,
            'rooms': [_room('etag-room')],
            'members': [_member('etag-member')],
          }),
          200,
          headers: const {
            'content-type': 'application/json; charset=utf-8',
            'etag': '"catalog-v1"',
          },
        );
      }
      return http.Response('', 304, headers: const {'etag': '"catalog-v1"'});
    });
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isTrue);
    final firstRefresh = service.lastRefreshedAt;
    expect(await service.refreshDiscovery(), isTrue);

    expect(requests, hasLength(2));
    expect(requests.first.headers.values, isNot(contains('"catalog-v1"')));
    expect(requests.last.headers.values, contains('"catalog-v1"'));
    expect(service.isPreviewCatalog, isFalse);
    expect(service.onlineCount, 8);
    expect(service.rooms.single.id, 'etag-room');
    expect(service.members.single.id, 'etag-member');
    expect(service.discoveryError, isNull);
    expect(service.lastRefreshedAt, isNotNull);
    expect(service.lastRefreshedAt!.isBefore(firstRefresh!), isFalse);
  });

  test('ignores malformed ETags and rejects their cache response', () async {
    final requests = <http.Request>[];
    var requestCount = 0;
    final client = MockClient((request) async {
      requests.add(request);
      requestCount += 1;
      if (requestCount == 1) {
        return http.Response(
          jsonEncode({
            'onlineCount': 6,
            'rooms': [_room('stable-room')],
            'members': [_member('stable-member')],
          }),
          200,
          headers: const {
            'content-type': 'application/json',
            'etag': 'not-a-quoted-validator',
          },
        );
      }
      return http.Response('', 304);
    });
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isTrue);
    expect(await service.refreshDiscovery(), isFalse);

    expect(requests, hasLength(2));
    expect(
      requests.last.headers.values,
      isNot(contains('not-a-quoted-validator')),
    );
    expect(service.isPreviewCatalog, isFalse);
    expect(service.rooms.single.id, 'stable-room');
    expect(service.discoveryError, contains('unvalidated cache'));
  });

  test('rejects a not-modified response before a catalog is cached', () async {
    final client = MockClient((_) async => http.Response('', 304));
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isFalse);
    expect(service.isPreviewCatalog, isTrue);
    expect(service.discoveryError, contains('unvalidated cache'));
  });

  test(
    'rejects non-success HTTP responses without replacing preview',
    () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"unavailable"}', 503),
      );
      final service = OnlineService(
        client: client,
        endpoint: 'https://api.example.com',
        automaticRefresh: false,
      );
      final previewRoomIds = service.rooms.map((room) => room.id).toList();
      addTearDown(() {
        service.dispose();
        client.close();
      });

      expect(await service.refreshDiscovery(), isFalse);
      expect(service.isPreviewCatalog, isTrue);
      expect(service.rooms.map((room) => room.id), previewRoomIds);
      expect(service.discoveryError, contains('503'));
    },
  );

  test('accepts an intentionally empty remote catalog', () async {
    final client = MockClient(
      (_) async => _jsonResponse({
        'onlineCount': 0,
        'rooms': <Object?>[],
        'members': <Object?>[],
      }),
    );
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isTrue);
    expect(service.isPreviewCatalog, isFalse);
    expect(service.onlineCount, 0);
    expect(service.rooms, isEmpty);
    expect(service.members, isEmpty);
  });

  test('bounds large room and member collections', () async {
    final client = MockClient(
      (_) async => _jsonResponse({
        'onlineCount': 120,
        'rooms': List.generate(60, (index) => _room('room-$index')),
        'members': List.generate(110, (index) => _member('member-$index')),
      }),
    );
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isTrue);
    expect(service.rooms, hasLength(50));
    expect(service.rooms.last.id, 'room-49');
    expect(service.members, hasLength(100));
    expect(service.members.last.id, 'member-99');
  });

  testWidgets('automatic refresh backs off and pauses outside the foreground', (
    tester,
  ) async {
    var requestCount = 0;
    final progressStates = <bool>[];
    late OnlineService service;
    final client = MockClient((_) async {
      requestCount += 1;
      progressStates.add(service.showsRefreshProgress);
      if (requestCount == 1) return http.Response('Unavailable', 503);
      return _jsonResponse({
        'onlineCount': requestCount,
        'rooms': [_room('room-$requestCount')],
        'members': [_member('member-$requestCount')],
      });
    });
    service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      refreshInterval: const Duration(seconds: 1),
      maximumRefreshInterval: const Duration(seconds: 4),
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isFalse);
    expect(requestCount, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(requestCount, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(requestCount, 2);
    expect(service.onlineCount, 2);
    expect(service.rooms.single.id, 'room-2');

    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(await service.refreshDiscovery(), isFalse);
    expect(requestCount, 2);

    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(requestCount, 3);
    expect(service.onlineCount, 3);
    expect(progressStates, [true, false, false]);
  });

  testWidgets('automatic refresh caps backoff and resets after success', (
    tester,
  ) async {
    var requestCount = 0;
    final progressStates = <bool>[];
    late OnlineService service;
    final client = MockClient((_) async {
      requestCount += 1;
      progressStates.add(service.showsRefreshProgress);
      if (requestCount <= 3) return http.Response('Unavailable', 503);
      return _jsonResponse({
        'onlineCount': requestCount,
        'rooms': [_room('room-$requestCount')],
        'members': [_member('member-$requestCount')],
      });
    });
    service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      refreshInterval: const Duration(seconds: 1),
      maximumRefreshInterval: const Duration(seconds: 4),
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    expect(await service.refreshDiscovery(), isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(requestCount, 2);

    await tester.pump(const Duration(seconds: 3));
    expect(requestCount, 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(requestCount, 3);

    await tester.pump(const Duration(seconds: 3));
    expect(requestCount, 3);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(requestCount, 4);
    expect(service.discoveryError, isNull);

    await tester.pump(const Duration(milliseconds: 999));
    expect(requestCount, 4);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(requestCount, 5);
    expect(progressStates, [true, false, false, false, false]);
  });

  test('background cancellation discards a late discovery response', () async {
    final requestStarted = Completer<void>();
    final serverResponse = Completer<http.StreamedResponse>();
    late http.AbortableRequest capturedRequest;
    final client = MockClient.streaming((request, _) {
      capturedRequest = request as http.AbortableRequest;
      requestStarted.complete();
      return serverResponse.future;
    });
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    final refreshing = service.refreshDiscovery();
    await requestStarted.future;
    expect(service.isRefreshing, isTrue);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(service.isRefreshing, isFalse);
    await expectLater(capturedRequest.abortTrigger, completes);

    serverResponse.complete(
      _jsonStreamedResponse({
        'onlineCount': 99,
        'rooms': [_room('late-room')],
        'members': [_member('late-member')],
      }),
    );

    expect(await refreshing, isFalse);
    expect(service.isPreviewCatalog, isTrue);
    expect(service.onlineCount, 0);
    expect(service.discoveryError, isNull);
  });

  testWidgets('times out and clears in-flight discovery state', (tester) async {
    final serverResponse = Completer<http.StreamedResponse>();
    late http.AbortableRequest capturedRequest;
    final client = MockClient.streaming((request, _) {
      capturedRequest = request as http.AbortableRequest;
      return serverResponse.future;
    });
    final service = OnlineService(
      client: client,
      endpoint: 'https://api.example.com',
      requestTimeout: const Duration(seconds: 1),
      automaticRefresh: false,
    );
    addTearDown(() {
      service.dispose();
      client.close();
    });

    final refreshing = service.refreshDiscovery();
    expect(service.isRefreshing, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(await refreshing, isFalse);
    expect(service.isRefreshing, isFalse);
    expect(service.isPreviewCatalog, isTrue);
    expect(service.discoveryError, contains('timed out'));
    await expectLater(capturedRequest.abortTrigger, completes);

    if (!serverResponse.isCompleted) {
      serverResponse.complete(
        _jsonStreamedResponse({
          'onlineCount': 0,
          'rooms': <Object?>[],
          'members': <Object?>[],
        }),
      );
      await tester.pump();
      expect(service.isPreviewCatalog, isTrue);
    }
  });

  test(
    'rejects responses larger than one MiB and retains preview data',
    () async {
      final oversized = jsonEncode({
        'onlineCount': 0,
        'rooms': <Object?>[],
        'members': <Object?>[],
        'padding': List.filled(1024 * 1024, 'x').join(),
      });
      final client = MockClient((_) async => http.Response(oversized, 200));
      final service = OnlineService(
        client: client,
        endpoint: 'https://api.example.com',
        automaticRefresh: false,
      );
      final previewRoomIds = service.rooms.map((room) => room.id).toList();
      final previewMemberIds = service.members
          .map((member) => member.id)
          .toList();
      addTearDown(() {
        service.dispose();
        client.close();
      });

      expect(await service.refreshDiscovery(), isFalse);
      expect(service.isPreviewCatalog, isTrue);
      expect(service.rooms.map((room) => room.id), previewRoomIds);
      expect(service.members.map((member) => member.id), previewMemberIds);
      expect(service.discoveryError, contains('too large'));
    },
  );
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

http.StreamedResponse _jsonStreamedResponse(Map<String, Object?> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    200,
    contentLength: bytes.length,
    headers: const {'content-type': 'application/json'},
  );
}

Map<String, Object?> _room(
  String id, {
  List<String> languageCodes = const ['en'],
}) {
  return {
    'id': id,
    'title': 'Room $id',
    'subtitle': 'A respectful room',
    'emoji': '🌍',
    'memberCount': 3,
    'languageCodes': languageCodes,
    'accentColor': '#123ABC',
  };
}

Map<String, Object?> _member(
  String id, {
  bool isOnline = true,
  int avatarSeed = 7,
}) {
  return {
    'id': id,
    'name': 'Member $id',
    'city': 'Dushanbe',
    'country': 'Tajikistan',
    'languageCode': 'tg',
    'avatarSeed': avatarSeed,
    'isVip': false,
    'isOnline': isOnline,
  };
}
