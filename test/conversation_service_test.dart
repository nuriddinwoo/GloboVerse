import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globoverse/models/conversation_message.dart';
import 'package:globoverse/services/conversation_service.dart';
import 'package:globoverse/services/online_service.dart';
import 'package:globoverse/services/translation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preview conversation translates both directions', () async {
    final translation = TranslationService();
    final online = OnlineService();
    final conversation = ConversationService(
      translation,
      online,
      previewConnectDelay: Duration.zero,
      previewReplyDelay: Duration.zero,
    );
    await translation.init();

    final starting = conversation.start(
      sourceLanguage: 'tg',
      targetLanguage: 'en',
    );
    expect(conversation.isStarting, isTrue);
    expect(
      await conversation.start(sourceLanguage: 'tg', targetLanguage: 'en'),
      isFalse,
    );
    expect(await starting, isTrue);
    expect(conversation.isStarting, isFalse);
    expect(conversation.isPreviewMode, isTrue);
    expect(conversation.peerName, 'GloboGuide');

    expect(await conversation.send('Салом'), isTrue);
    expect(conversation.messages, hasLength(2));
    expect(conversation.messages.first.sender, ConversationMessageSender.me);
    expect(conversation.messages.first.translatedText, 'Hello');
    expect(conversation.messages.last.sender, ConversationMessageSender.peer);
    expect(conversation.messages.last.translatedText, 'Аз шиносоӣ шодам');
    expect(await conversation.reportCurrent('other'), isTrue);
    expect(conversation.isReported, isTrue);

    await conversation.end();
    conversation.dispose();
    translation.dispose();
    online.dispose();
  });

  test(
    'remote conversation parses the session and incoming messages',
    () async {
      final translation = TranslationService();
      final online = OnlineService();
      final requests = <http.Request>[];
      final peerTimestamp = DateTime.now().toUtc().toIso8601String();
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && request.url.path == '/sessions') {
          return http.Response(
            '{"id":"session-1","peer":{"name":"Amina"}}',
            201,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/messages') {
          return http.Response(
            '{"messages":[{"id":"peer-1","sender":"peer",'
            '"text":"Hello","sourceLanguage":"en","targetLanguage":"tg",'
            '"timestamp":"$peerTimestamp"},{"id":"","text":"ignored"}]}',
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-1/reports') {
          return http.Response('{}', 201);
        }
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response('Not found', 404);
      });
      final conversation = ConversationService(
        translation,
        online,
        client: client,
        endpoint: 'https://api.example.com',
        automaticPolling: false,
        apiToken: 'test-token',
      );
      await translation.init();

      expect(
        await conversation.start(sourceLanguage: 'tg', targetLanguage: 'en'),
        isTrue,
      );
      expect(requests.first.headers.values, contains('Bearer test-token'));
      expect(conversation.sessionId, 'session-1');
      expect(conversation.peerName, 'Amina');
      expect(await conversation.send('Салом'), isTrue);
      expect(conversation.messages, hasLength(2));
      expect(conversation.messages.last.id, 'peer-1');
      expect(conversation.messages.last.translatedText, 'Салом');
      expect(requests, hasLength(2));
      expect(await conversation.reportCurrent('not-a-valid-reason'), isFalse);
      expect(requests, hasLength(2));
      expect(await conversation.reportCurrent('spam'), isTrue);
      expect(requests.last.url.path, '/sessions/session-1/reports');
      expect(jsonDecode(requests.last.body), containsPair('reason', 'spam'));

      await conversation.end();
      expect(requests.last.method, 'DELETE');
      conversation.dispose();
      translation.dispose();
      online.dispose();
    },
  );

  testWidgets('automatic polling stops when the session ends', (tester) async {
    final translation = TranslationService();
    final online = OnlineService();
    var pollRequests = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/sessions') {
        return http.Response('{"id":"session-timer"}', 201);
      }
      if (request.method == 'GET') {
        pollRequests += 1;
        return http.Response('{"cursor":"timer-cursor"}', 200);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('Not found', 404);
    });
    final conversation = ConversationService(
      translation,
      online,
      client: client,
      endpoint: 'https://api.example.com',
      pollInterval: const Duration(seconds: 1),
      maximumPollInterval: const Duration(seconds: 2),
    );
    await translation.init();
    await conversation.start(sourceLanguage: 'en', targetLanguage: 'tg');

    conversation.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(pollRequests, 0);

    conversation.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(pollRequests, 1);

    await conversation.end();
    await tester.pump(const Duration(seconds: 3));
    expect(pollRequests, 1);

    conversation.dispose();
    translation.dispose();
    online.dispose();
  });

  test(
    'polling appends messages, advances cursors, and applies receipts',
    () async {
      final translation = TranslationService();
      final online = OnlineService();
      final requests = <http.Request>[];
      final timestamp = DateTime.now().toUtc().toIso8601String();
      String? sentMessageId;
      var pollCount = 0;
      var failNextPoll = false;
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && request.url.path == '/sessions') {
          return http.Response(
            '{"id":"session-live","cursor":"cursor-1"}',
            201,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-live/messages') {
          final body = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          sentMessageId = body['id'] as String;
          return http.Response('{}', 200);
        }
        if (request.method == 'GET' &&
            request.url.path == '/sessions/session-live/messages') {
          if (failNextPoll) {
            failNextPoll = false;
            return http.Response('Temporary failure', 503);
          }
          pollCount += 1;
          return http.Response(
            jsonEncode({
              'cursor': pollCount == 1 ? 'cursor-2' : 'cursor-3',
              'messages': [
                {
                  'id': 'peer-live-1',
                  'sender': 'peer',
                  'text': 'Hello',
                  'sourceLanguage': 'en',
                  'targetLanguage': 'tg',
                  'timestamp': timestamp,
                },
              ],
              'receipts': [
                {
                  'messageId': sentMessageId,
                  'deliveryState': pollCount == 1 ? 'read' : 'delivered',
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/sessions/session-live/read') {
          return http.Response('{}', 200);
        }
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response('Not found', 404);
      });
      final conversation = ConversationService(
        translation,
        online,
        client: client,
        endpoint: 'https://api.example.com',
        automaticPolling: false,
      );
      await translation.init();
      expect(
        await conversation.start(sourceLanguage: 'tg', targetLanguage: 'en'),
        isTrue,
      );
      expect(await conversation.send('Салом'), isTrue);

      expect(await conversation.syncNow(), isTrue);
      final firstPoll = requests.firstWhere(
        (request) => request.method == 'GET',
      );
      expect(firstPoll.url.queryParameters['after'], 'cursor-1');
      expect(conversation.messages, hasLength(2));
      expect(
        conversation.messages.first.deliveryState,
        MessageDeliveryState.read,
      );
      expect(conversation.messages.last.translatedText, 'Салом');
      expect(conversation.lastSyncedAt, isNotNull);

      expect(await conversation.markIncomingRead(), isTrue);
      final readRequest = requests.lastWhere(
        (request) => request.url.path == '/sessions/session-live/read',
      );
      final readBody = Map<String, dynamic>.from(
        jsonDecode(readRequest.body) as Map,
      );
      expect(readBody['messageIds'], ['peer-live-1']);

      expect(await conversation.syncNow(), isTrue);
      final polls = requests
          .where((request) => request.method == 'GET')
          .toList();
      expect(polls.last.url.queryParameters['after'], 'cursor-2');
      expect(conversation.messages, hasLength(2));
      expect(
        conversation.messages.first.deliveryState,
        MessageDeliveryState.read,
      );

      failNextPoll = true;
      expect(await conversation.syncNow(), isFalse);
      expect(conversation.isReconnecting, isTrue);
      expect(conversation.syncError, isNotNull);
      expect(await conversation.syncNow(), isTrue);
      expect(conversation.isReconnecting, isFalse);
      expect(conversation.syncError, isNull);

      await conversation.end();
      conversation.dispose();
      translation.dispose();
      online.dispose();
    },
  );

  test('late poll responses are discarded after a session ends', () async {
    final translation = TranslationService();
    final online = OnlineService();
    final pollResponse = Completer<http.Response>();
    final pollStarted = Completer<void>();
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/sessions') {
        return http.Response('{"id":"session-poll"}', 201);
      }
      if (request.method == 'GET') {
        pollStarted.complete();
        return pollResponse.future;
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('Not found', 404);
    });
    final conversation = ConversationService(
      translation,
      online,
      client: client,
      endpoint: 'https://api.example.com',
      automaticPolling: false,
    );
    await translation.init();
    await conversation.start(sourceLanguage: 'tg', targetLanguage: 'en');

    final syncing = conversation.syncNow();
    await pollStarted.future;
    await conversation.end();
    pollResponse.complete(
      http.Response(
        '{"cursor":"late","message":{"id":"late-poll",'
        '"sender":"peer","text":"Hello"}}',
        200,
      ),
    );

    expect(await syncing, isFalse);
    expect(conversation.messages, isEmpty);
    expect(conversation.status, ConversationStatus.ended);

    conversation.dispose();
    translation.dispose();
    online.dispose();
  });

  test('malformed session responses are rejected', () async {
    final translation = TranslationService();
    final online = OnlineService();
    final client = MockClient(
      (_) async => http.Response('{"id":42,"messages":"invalid"}', 200),
    );
    final conversation = ConversationService(
      translation,
      online,
      client: client,
      endpoint: 'https://api.example.com',
      automaticPolling: false,
    );
    await translation.init();

    expect(
      await conversation.start(sourceLanguage: 'en', targetLanguage: 'tg'),
      isFalse,
    );
    expect(conversation.status, ConversationStatus.error);
    expect(conversation.sessionId, isNull);
    expect(conversation.error, contains('session ID'));

    conversation.dispose();
    translation.dispose();
    online.dispose();
  });

  test('retry preserves the client message ID', () async {
    final translation = TranslationService();
    final online = OnlineService();
    final submittedBodies = <Map<String, dynamic>>[];
    var submissionCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/sessions') {
        return http.Response('{"id":"session-2"}', 201);
      }
      if (request.url.path == '/sessions/session-2/messages') {
        submittedBodies.add(
          Map<String, dynamic>.from(jsonDecode(request.body) as Map),
        );
        submissionCount += 1;
        return submissionCount == 1
            ? http.Response('Temporary failure', 503)
            : http.Response('{}', 200);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('Not found', 404);
    });
    final conversation = ConversationService(
      translation,
      online,
      client: client,
      endpoint: 'https://api.example.com',
      automaticPolling: false,
    );
    await translation.init();
    await conversation.start(sourceLanguage: 'tg', targetLanguage: 'en');

    expect(await conversation.send('Салом'), isFalse);
    final failed = conversation.messages.single;
    expect(failed.deliveryState, MessageDeliveryState.failed);
    expect(await conversation.retry(failed.id), isTrue);

    expect(conversation.messages.single.id, failed.id);
    expect(
      conversation.messages.single.deliveryState,
      MessageDeliveryState.sent,
    );
    expect(submittedBodies, hasLength(2));
    expect(submittedBodies.first['id'], submittedBodies.last['id']);

    await conversation.end();
    conversation.dispose();
    translation.dispose();
    online.dispose();
  });

  test('discovery refresh notifications do not force a chat poll', () async {
    final translation = TranslationService();
    final discoveryClient = MockClient(
      (_) async =>
          http.Response('{"onlineCount":0,"rooms":[],"members":[]}', 200),
    );
    final online = OnlineService(
      client: discoveryClient,
      endpoint: 'https://discovery.example.com',
      automaticRefresh: false,
    );
    var pollRequests = 0;
    final chatClient = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/sessions') {
        return http.Response('{"id":"quiet-session"}', 201);
      }
      if (request.method == 'GET') {
        pollRequests += 1;
        return http.Response('{}', 200);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('Not found', 404);
    });
    final conversation = ConversationService(
      translation,
      online,
      client: chatClient,
      endpoint: 'https://api.example.com',
      pollInterval: const Duration(hours: 1),
      maximumPollInterval: const Duration(hours: 1),
    );
    await translation.init();
    expect(
      await conversation.start(sourceLanguage: 'en', targetLanguage: 'tg'),
      isTrue,
    );

    expect(await online.refreshDiscovery(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(pollRequests, 0);

    await conversation.end();
    conversation.dispose();
    translation.dispose();
    online.dispose();
    discoveryClient.close();
    chatClient.close();
  });

  test('only validated remote discovery identities reach chat', () async {
    final translation = TranslationService();
    final discoveryClient = MockClient(
      (_) async => http.Response(
        '{"onlineCount":1,"rooms":[{"id":"remote-room",'
        '"title":"Remote room","subtitle":"Live", "emoji":"🌍",'
        '"memberCount":1,"languageCodes":["en","tg"],'
        '"accentColor":"#123ABC"}],"members":[{"id":"remote-member",'
        '"name":"Remote member","city":"Dushanbe",'
        '"country":"Tajikistan","languageCode":"tg",'
        '"isOnline":true}]}',
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final online = OnlineService(
      client: discoveryClient,
      endpoint: 'https://discovery.example.com',
      automaticRefresh: false,
    );
    final startBodies = <Map<String, dynamic>>[];
    final chatClient = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/sessions') {
        startBodies.add(
          Map<String, dynamic>.from(jsonDecode(request.body) as Map),
        );
        return http.Response('{"id":"safe-session"}', 201);
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('Not found', 404);
    });
    final conversation = ConversationService(
      translation,
      online,
      client: chatClient,
      endpoint: 'https://api.example.com',
      automaticPolling: false,
    );
    await translation.init();

    expect(
      await conversation.start(
        sourceLanguage: 'en',
        targetLanguage: 'tg',
        room: online.rooms.first,
        member: online.members.first,
      ),
      isTrue,
    );
    expect(startBodies.single, isNot(contains('roomId')));
    expect(startBodies.single, isNot(contains('peerId')));
    await conversation.end();

    expect(await online.refreshDiscovery(), isTrue);
    expect(
      await conversation.start(
        sourceLanguage: 'en',
        targetLanguage: 'tg',
        room: online.rooms.first,
        member: online.members.first,
      ),
      isTrue,
    );
    expect(startBodies.last['roomId'], 'remote-room');
    expect(startBodies.last['peerId'], 'remote-member');

    await conversation.end();
    conversation.dispose();
    translation.dispose();
    online.dispose();
    discoveryClient.close();
    chatClient.close();
  });

  test('late remote replies cannot revive an ended session', () async {
    final translation = TranslationService();
    final online = OnlineService();
    final response = Completer<http.Response>();
    final messageStarted = Completer<void>();
    final client = MockClient((request) async {
      if (request.url.path == '/sessions') {
        return http.Response('{"id":"session-3"}', 201);
      }
      if (request.url.path == '/sessions/session-3/messages') {
        if (!messageStarted.isCompleted) messageStarted.complete();
        return response.future;
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('Not found', 404);
    });
    final conversation = ConversationService(
      translation,
      online,
      client: client,
      endpoint: 'https://api.example.com',
      automaticPolling: false,
    );
    await translation.init();
    await conversation.start(sourceLanguage: 'tg', targetLanguage: 'en');

    final sending = conversation.send('Салом');
    await messageStarted.future;
    await conversation.end();
    response.complete(
      http.Response(
        '{"message":{"id":"late","sender":"peer","text":"Hello"}}',
        200,
      ),
    );

    expect(await sending, isFalse);
    expect(conversation.status, ConversationStatus.ended);
    expect(conversation.messages, isEmpty);

    conversation.dispose();
    translation.dispose();
    online.dispose();
  });
}
