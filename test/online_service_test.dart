import 'dart:convert';

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

  test(
    'rejects non-success HTTP responses without replacing preview',
    () async {
      final client = MockClient(
        (_) async => http.Response('{"error":"unavailable"}', 503),
      );
      final service = OnlineService(
        client: client,
        endpoint: 'https://api.example.com',
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
